#!/usr/bin/env bash
#
# Google's Android agent skills, installed PER PROJECT in tiers (committed under .claude/skills/, so
# a fresh clone, a cloud session and the autonomous loop all have them). The tier lists below are the
# single source of truth — docs/android-cli.md mirrors them; change both together.
#
# Usage:
#   skills.sh tiers
#       Print every tier and its skills.
#   skills.sh install <project-dir> <tier>...
#       `android skills add --project <dir> --agent claude-code <id>` for every skill of the tiers
#       (skips skills already installed). Tiers: baseline, desktop, xr, glasses, cars, tv, wear,
#       cast, widgets, camerax, appfunctions, genai, litert, credentials, billing, engage, adopt.
#   skills.sh check <project-dir> <tier>...
#       Report missing skills of the tiers (exit 1 when any is missing). Used by /android-forge-doctor.
#   skills.sh update <project-dir>
#       `android skills update --all` for the project's installed skills.

set -euo pipefail

die() { echo "skills: $*" >&2; exit 1; }

tier_skills() {
    case "$1" in
        # Every project: device/QA tooling, the adaptive phone/tablet/foldable baseline, navigation,
        # insets, testing, performance, security review and release hygiene.
        baseline) echo "android-cli adaptive navigation-3 navigation-event edge-to-edge testing-setup jetpack-compose-performance android-profiler android-intent-security android-permissions-security r8-analyzer play-policy-insights" ;;
        # Form factors (/android-forge-add-form-factor). Same-APK surfaces lean on `adaptive`.
        desktop)  echo "adaptive" ;;
        xr)       echo "adaptive" ;;
        glasses)  echo "display-glasses-with-jetpack-compose-glimmer" ;;
        cars)     echo "android-for-cars-parked-apps" ;;
        tv)       echo "leanback-to-compose-tv-migration engage-sdk-integration" ;;
        wear)     echo "wear-compose-m3 wear-widgets" ;;
        cast)     echo "media3-cast-integration" ;;
        widgets)  echo "glance-canonical-layouts" ;;
        # Capabilities (/android-forge-add-library maps the library to its tier).
        camerax)      echo "camerax" ;;
        appfunctions) echo "appfunctions" ;;
        genai)        echo "ml-kit-genai-prompt-api" ;;
        litert)       echo "litert-runtime" ;;
        credentials)  echo "restore-credentials verified-email" ;;
        billing)      echo "play-billing-library-version-upgrade" ;;
        engage)       echo "engage-sdk-integration" ;;
        # Migrating an existing project (/android-forge-adopt suggests these; never installed by init).
        adopt)        echo "agp-9-upgrade migrate-xml-views-to-jetpack-compose styles" ;;
        *) die "unknown tier: $1" ;;
    esac
}

ALL_TIERS="baseline desktop xr glasses cars tv wear cast widgets camerax appfunctions genai litert credentials billing engage adopt"

installed_skills() {
    local project="$1"
    [[ -d "$project/.claude/skills" ]] || return 0
    local d
    for d in "$project/.claude/skills"/*/; do
        [[ -f "${d}SKILL.md" ]] && basename "$d"
    done
    return 0
}

cmd_tiers() {
    for t in $ALL_TIERS; do printf '%-13s %s\n' "$t" "$(tier_skills "$t")"; done
}

# Fail on an unknown tier before doing anything (tier_skills' `die` can't stop the script from inside
# the `$(…)` of a for-list).
require_tiers() {
    local t
    for t in "$@"; do tier_skills "$t" >/dev/null; done
}

cmd_install() {
    local project="$1"; shift
    require_tiers "$@"
    command -v android >/dev/null || die "the Android CLI ('android') is not on PATH — run /android-forge-doctor"
    [[ -d "$project" ]] || die "project dir not found: $project"
    local have; have="$(installed_skills "$project")"
    for t in "$@"; do
        for s in $(tier_skills "$t"); do
            if grep -qx "$s" <<< "$have"; then
                echo "skip (installed): $s"
            else
                android skills add --project="$project" --agent=claude-code "$s"
                have="$have"$'\n'"$s"
            fi
        done
    done
}

cmd_check() {
    local project="$1"; shift
    require_tiers "$@"
    local have missing=0; have="$(installed_skills "$project")"
    for t in "$@"; do
        for s in $(tier_skills "$t"); do
            if grep -qx "$s" <<< "$have"; then echo "✓ $s ($t)"; else echo "✗ $s ($t) — missing"; missing=1; fi
        done
    done
    return "$missing"
}

cmd_update() {
    local project="$1"
    command -v android >/dev/null || die "the Android CLI ('android') is not on PATH"
    android skills update --all --project="$project" --agent=claude-code
}

main() {
    [[ $# -ge 1 ]] || die "usage: $0 <tiers|install|check|update> ..."
    local cmd="$1"; shift
    case "$cmd" in
        tiers)   cmd_tiers ;;
        install) [[ $# -ge 2 ]] || die "install <project-dir> <tier>..."; cmd_install "$@" ;;
        check)   [[ $# -ge 2 ]] || die "check <project-dir> <tier>..."; cmd_check "$@" ;;
        update)  [[ $# -eq 1 ]] || die "update <project-dir>"; cmd_update "$@" ;;
        *)       die "unknown sub-command: $cmd" ;;
    esac
}

main "$@"
