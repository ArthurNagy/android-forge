#!/usr/bin/env bash
#
# Emulators per form factor, for QA journeys and manual checks. The Android CLI's
# `android emulator create` only knows phone / tablet / desktop profiles, so every other form factor
# is created with the SDK's avdmanager from a hardware profile + a system image that
# `android sdk install` downloads. AVDs are named after their hardware profile; `android emulator
# start <name>` boots any of them.
#
# This table is the source of truth for form factor → AVD; docs/android-cli.md mirrors it.
#
# Usage:
#   avd.sh name <form-factor>      print the AVD name (QA uses this; no side effects)
#   avd.sh status                  per form factor: system image installed? AVD present?
#   avd.sh ensure <form-factor>    install the system image if missing (GBs — callers ask first) and
#                                  create the AVD if missing. Idempotent (a TV AVD not yet prepared is
#                                  prepared, see below).
#   avd.sh prepare tv              boot the TV AVD (or use it if it's running) and turn Play Protect's app
#                                  verification off in it; re-runnable. Marked done in the AVD's directory.
#
# Form factors: phone tablet desktop foldable wear tv automotive xr glasses
# (Android Auto runs in the Desktop Head Unit — `android sdk install extras/google/auto`; Cast needs real hardware.)

set -euo pipefail

die() { echo "avd: $*" >&2; exit 1; }

FORM_FACTORS="phone tablet desktop foldable wear tv automotive xr glasses"

abi() {
    # A shell under Rosetta reports x86_64 on Apple silicon — ask the hardware.
    if [[ "$(uname -s)" == Darwin && "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]]; then
        echo "arm64-v8a"; return
    fi
    case "$(uname -m)" in
        arm64|aarch64) echo "arm64-v8a" ;;
        *) echo "x86_64" ;;
    esac
}

# Fail on an unknown form factor in the main shell (spec's `die` only ends a `$(…)` subshell).
require_ff() {
    case " ${FORM_FACTORS} " in
        *" $1 "*) ;;
        *) die "unknown form factor: $1 (one of: ${FORM_FACTORS})" ;;
    esac
}

# form factor → "<avd name>|<hardware profile>|<system image (android sdk path, '/' separated) or 'cli'>"
spec() {
    local a; a="$(abi)"
    case "$1" in
        phone)      echo "medium_phone|medium_phone|cli" ;;
        tablet)     echo "medium_tablet|medium_tablet|cli" ;;
        # The CLI names its desktop AVD desktop_medium (profile medium_desktop).
        desktop)    echo "desktop_medium|medium_desktop|cli" ;;
        foldable)   echo "pixel_10_pro_fold|pixel_10_pro_fold|system-images/android-37.0/google_apis_playstore_ps16k/${a}" ;;
        wear)       echo "wearos_large_round|wearos_large_round|system-images/android-37.0/android-wear-signed/${a}" ;;
        # TV images ship Play Protect, which blocks the Android CLI's instrumentation server ("built for an older
        # version of Android") — ensure turns app verification off once, inside this AVD only (prepare_tv).
        tv)         echo "tv_1080p|tv_1080p|system-images/android-36/android-tv/${a}" ;;
        automotive) echo "automotive_1408p_landscape_with_play|automotive_1408p_landscape_with_play|system-images/android-35-ext15/android-automotive-playstore/${a}" ;;
        xr)         echo "xr_headset_device|xr_headset_device|system-images/android-34/google-xr/${a}" ;;
        glasses)    echo "ai_glasses_device|ai_glasses_device|system-images/android-36/ai-glasses/${a}" ;;
        *) die "unknown form factor: $1 (one of: ${FORM_FACTORS})" ;;
    esac
}

field() { cut -d'|' -f"$2" <<< "$1"; }

sdk_root() {
    local s; s="$(android info sdk 2>/dev/null || true)"
    [[ -n "${s}" ]] || s="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
    [[ -n "${s}" ]] || die "no Android SDK found (android info sdk / ANDROID_HOME)"
    echo "${s}"
}

avdmanager_bin() {
    local b; b="$(sdk_root)/cmdline-tools/latest/bin/avdmanager"
    [[ -x "${b}" ]] && { echo "${b}"; return; }
    command -v avdmanager || die "avdmanager not found — android sdk install cmdline-tools/latest"
}

adb_bin() {
    local b; b="$(sdk_root)/platform-tools/adb"
    [[ -x "${b}" ]] && { echo "${b}"; return; }
    command -v adb || die "adb not found — android sdk install platform-tools"
}

avd_exists() { android emulator list 2>/dev/null | grep -qx "$1"; }

# The AVD's directory (<avd home>/<name>.ini's path=, else <avd home>/<name>.avd).
avd_dir() {
    local home="${ANDROID_AVD_HOME:-${ANDROID_USER_HOME:-${HOME}/.android}/avd}" p=""
    [[ -f "${home}/$1.ini" ]] && p="$(sed -n 's/^path=//p' "${home}/$1.ini" | head -1)"
    [[ -n "${p}" && -d "${p}" ]] || p="${home}/$1.avd"
    echo "${p}"
}

TV_MARKER="android-forge-tv-prepared"
tv_prepared() { [[ -f "$(avd_dir "$1")/${TV_MARKER}" ]]; }

# Serial of the running emulator booted from AVD <name> (empty when none).
running_serial() {
    local adb="$1" name="$2" serial n
    for serial in $("${adb}" devices | awk '/^emulator-[0-9]+[[:space:]]+device/{print $1}'); do
        # The emulator console's answer, else the guest's property (console auth can refuse `emu`).
        n="$("${adb}" -s "${serial}" emu avd name 2>/dev/null | head -1 | tr -d '\r' || true)"
        [[ "${n}" == "${name}" ]] || n="$("${adb}" -s "${serial}" shell getprop ro.boot.qemu.avd_name 2>/dev/null | tr -d '\r' || true)"
        if [[ "${n}" == "${name}" ]]; then echo "${serial}"; return; fi
    done
}

image_installed() { [[ -d "$(sdk_root)/$1" ]]; }

cmd_name() { require_ff "$1"; field "$(spec "$1")" 1; }

# Turn off Play Protect's app verification — in this TV emulator only — so the Android CLI can install its
# layout/input instrumentation server. The setting persists in the AVD's userdata; a marker file in the AVD's
# directory records it, so `ensure tv` retries until it succeeds. Boots the AVD unless it's already running.
prepare_tv() {
    local name="$1" adb serial started=""
    avd_exists "${name}" || die "AVD ${name} not found — create it first: avd.sh ensure tv"
    adb="$(adb_bin)"
    serial="$(running_serial "${adb}" "${name}")"
    if [[ -z "${serial}" ]]; then
        android emulator start "${name}" >/dev/null
        started=1
        serial="$(running_serial "${adb}" "${name}")"
    fi
    [[ -n "${serial}" ]] || die "could not find the running ${name} emulator — re-run: avd.sh prepare tv"
    "${adb}" -s "${serial}" wait-for-device
    "${adb}" -s "${serial}" shell settings put global package_verifier_enable 0
    "${adb}" -s "${serial}" shell settings put global verifier_verify_adb_installs 0
    if [[ -n "${started}" ]]; then android emulator stop "${name}" >/dev/null; fi
    touch "$(avd_dir "${name}")/${TV_MARKER}"
    echo "TV emulator prepared: Play Protect app verification off (CLI instrumentation allowed)"
}

cmd_prepare() {
    [[ "$1" == tv ]] || die "prepare: only tv needs preparing (got: $1)"
    command -v android >/dev/null || die "the Android CLI ('android') is not on PATH"
    prepare_tv "$(field "$(spec tv)" 1)"
}

cmd_status() {
    command -v android >/dev/null || die "the Android CLI ('android') is not on PATH"
    for ff in ${FORM_FACTORS}; do
        local s name image img_state avd_state
        s="$(spec "${ff}")"; name="$(field "${s}" 1)"; image="$(field "${s}" 3)"
        if [[ "${image}" == cli ]]; then img_state="(CLI default image)"
        elif image_installed "${image}"; then img_state="image ✓"
        else img_state="image ✗ ${image}"; fi
        if ! avd_exists "${name}"; then avd_state="AVD ✗ ${name}"
        elif [[ "${ff}" == tv ]] && ! tv_prepared "${name}"; then avd_state="AVD ✓ ${name} (unprepared: avd.sh prepare tv)"
        else avd_state="AVD ✓ ${name}"; fi
        printf '%-11s %-40s %s\n' "${ff}" "${avd_state}" "${img_state}"
    done
}

cmd_ensure() {
    local ff="$1" s name profile image
    require_ff "${ff}"
    command -v android >/dev/null || die "the Android CLI ('android') is not on PATH"
    s="$(spec "${ff}")"; name="$(field "${s}" 1)"; profile="$(field "${s}" 2)"; image="$(field "${s}" 3)"
    if avd_exists "${name}"; then
        echo "AVD present: ${name}"
        if [[ "${ff}" == tv ]] && ! tv_prepared "${name}"; then prepare_tv "${name}"; fi
        return
    fi
    if [[ "${image}" == cli ]]; then
        android emulator create "${profile}"
    else
        image_installed "${image}" || android sdk install "${image}"
        # avdmanager wants ';' separators; "no" declines the custom hardware profile prompt.
        echo "no" | "$(avdmanager_bin)" create avd --name "${name}" --device "${profile}" --package "${image//\//;}"
    fi
    avd_exists "${name}" || die "AVD ${name} was not created"
    [[ "${ff}" == tv ]] && prepare_tv "${name}"
    echo "AVD ready: ${name} — boot it with: android emulator start ${name}"
}

main() {
    [[ $# -ge 1 ]] || die "usage: $0 <name|status|ensure|prepare> [form-factor]"
    local cmd="$1"; shift
    case "${cmd}" in
        name)   [[ $# -eq 1 ]] || die "name <form-factor>"; cmd_name "$@" ;;
        status) cmd_status ;;
        ensure) [[ $# -eq 1 ]] || die "ensure <form-factor>"; cmd_ensure "$@" ;;
        prepare) [[ $# -eq 1 ]] || die "prepare tv"; cmd_prepare "$@" ;;
        *)      die "unknown sub-command: ${cmd}" ;;
    esac
}

main "$@"
