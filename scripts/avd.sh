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
#                                  create the AVD if missing. Idempotent.
#
# Form factors: phone tablet desktop foldable wear tv automotive xr glasses
# (Android Auto runs in the Desktop Head Unit — `android sdk install extras/google/auto`; Cast needs real hardware.)

set -euo pipefail

die() { echo "avd: $*" >&2; exit 1; }

FORM_FACTORS="phone tablet desktop foldable wear tv automotive xr glasses"

abi() {
    case "$(uname -m)" in
        arm64|aarch64) echo "arm64-v8a" ;;
        *) echo "x86_64" ;;
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

avd_exists() { android emulator list 2>/dev/null | grep -qx "$1"; }

image_installed() { [[ -d "$(sdk_root)/$1" ]]; }

cmd_name() { field "$(spec "$1")" 1; }

# Boot the new TV AVD once and turn off Play Protect's app verification — in this emulator only — so the Android CLI
# can install its layout/input instrumentation server. The setting persists in the AVD's userdata.
prepare_tv() {
    local name="$1" before serial
    before="$(adb devices | awk '/^emulator-/{print $1}')"
    android emulator start "${name}" >/dev/null
    serial="$(adb devices | awk '/^emulator-/{print $1}' | grep -vxF -f <(printf '%s\n' ${before}) | head -1 || true)"
    if [[ -z "${serial}" ]]; then
        echo "⚠ could not identify the booted ${name} emulator — turn off Play Protect app verification in its Settings by hand" >&2
        return 0
    fi
    adb -s "${serial}" shell settings put global package_verifier_enable 0
    adb -s "${serial}" shell settings put global verifier_verify_adb_installs 0
    android emulator stop "${name}" >/dev/null
    echo "TV emulator prepared: Play Protect app verification off (CLI instrumentation allowed)"
}

cmd_status() {
    command -v android >/dev/null || die "the Android CLI ('android') is not on PATH"
    for ff in ${FORM_FACTORS}; do
        local s name image img_state avd_state
        s="$(spec "${ff}")"; name="$(field "${s}" 1)"; image="$(field "${s}" 3)"
        if [[ "${image}" == cli ]]; then img_state="(CLI default image)"
        elif image_installed "${image}"; then img_state="image ✓"
        else img_state="image ✗ ${image}"; fi
        if avd_exists "${name}"; then avd_state="AVD ✓ ${name}"; else avd_state="AVD ✗ ${name}"; fi
        printf '%-11s %-40s %s\n' "${ff}" "${avd_state}" "${img_state}"
    done
}

cmd_ensure() {
    local ff="$1" s name profile image
    command -v android >/dev/null || die "the Android CLI ('android') is not on PATH"
    s="$(spec "${ff}")"; name="$(field "${s}" 1)"; profile="$(field "${s}" 2)"; image="$(field "${s}" 3)"
    if avd_exists "${name}"; then
        echo "AVD present: ${name}"
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
    [[ $# -ge 1 ]] || die "usage: $0 <name|status|ensure> [form-factor]"
    local cmd="$1"; shift
    case "${cmd}" in
        name)   [[ $# -eq 1 ]] || die "name <form-factor>"; cmd_name "$@" ;;
        status) cmd_status ;;
        ensure) [[ $# -eq 1 ]] || die "ensure <form-factor>"; cmd_ensure "$@" ;;
        *)      die "unknown sub-command: ${cmd}" ;;
    esac
}

main "$@"
