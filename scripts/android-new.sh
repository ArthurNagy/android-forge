#!/usr/bin/env bash
#
# Create a new Android project with Google's Android CLI (`android create`) and prepare it for the
# android-forge overlay. Used by /android-forge-init.
#
# Usage:
#   android-new.sh create <app-name> <application-id> <min-sdk> <target-dir>
#       Run `android create empty-activity` into <target-dir> (or, when <target-dir> already has
#       files, into "<target-dir>.android-create" and copy over WITHOUT overwriting anything), then
#       `prepare` it.
#
#   android-new.sh prepare <target-dir> <min-sdk>
#       Idempotent post-processing of `android create`'s output — every step the overlay relies on:
#         - delete the template's sample code (app/src/{main,test,androidTest}/java): android-forge's
#           :app overlay replaces it, under src/*/kotlin
#         - merge res/mipmap-anydpi-v26 into res/mipmap-anydpi when minSdk >= 26 (Lint ObsoleteSdkInt)
#         - manifest: android:name=".MainApplication" (Hilt's application) and the backup rules the
#           template ships but never references (Lint UnusedResources)
#         - settings.gradle.kts: includeBuild("build-logic") inside pluginManagement { }
#         - root build.gradle.kts: only `id("android-forge.root")` — every plugin comes from build-logic,
#           so the template's `alias(libs.plugins.x) apply false` lines would clash ("already on the
#           classpath with an unknown version")
#
#   android-new.sh ensure-sdk <compile-sdk>
#       Install platforms/android-<compile-sdk>.0 (falling back to android-<compile-sdk>) with
#       `android sdk install` when no installed platform matches. Idempotent.
#
# Exit codes: 0 ok · 1 usage / precondition error · 2 `android create` failed.

set -euo pipefail

die() { echo "android-new: $*" >&2; exit 1; }

require_android() {
    command -v android >/dev/null || die "the Android CLI ('android') is not on PATH — run /android-forge-doctor"
}

cmd_ensure_sdk() {
    local api="$1"
    require_android
    if android sdk list 2>/dev/null | sed -n '/Installed packages/,/Available/p' | grep -qE "^\s*platforms/android-${api}(\.[0-9]+)?\s"; then
        echo "sdk: platforms/android-${api}* already installed"
        return
    fi
    android sdk install "platforms/android-${api}.0" || android sdk install "platforms/android-${api}"
}

cmd_prepare() {
    local target="$1" min_sdk="$2"
    [[ -f "$target/settings.gradle.kts" && -d "$target/app" ]] || die "not an android create project: $target"

    for set in main test androidTest; do
        rm -rf "$target/app/src/$set/java"
    done

    local res="$target/app/src/main/res"
    if [[ "$min_sdk" -ge 26 && -d "$res/mipmap-anydpi-v26" ]]; then
        mkdir -p "$res/mipmap-anydpi"
        mv -n "$res/mipmap-anydpi-v26/"* "$res/mipmap-anydpi/"
        rmdir "$res/mipmap-anydpi-v26" 2>/dev/null || true
    fi

    python3 - "$target" <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])

manifest = root / "app/src/main/AndroidManifest.xml"
m = manifest.read_text()
attrs = [
    ('android:name=', 'android:name=".MainApplication"'),
    ('android:dataExtractionRules=', 'android:dataExtractionRules="@xml/data_extraction_rules"'),
    ('android:fullBackupContent=', 'android:fullBackupContent="@xml/backup_rules"'),
]
app_tag = re.search(r"<application\b([^>]*)>", m, re.S)
if not app_tag:
    sys.exit("android-new: no <application> tag in AndroidManifest.xml")
tag = app_tag.group(0)
new_tag = tag
for probe, attr in attrs:
    if probe not in tag:
        new_tag = new_tag.replace("<application", "<application\n        " + attr, 1)
if new_tag != tag:
    manifest.write_text(m.replace(tag, new_tag, 1))
    print("manifest: application name + backup rules wired")

settings = root / "settings.gradle.kts"
s = settings.read_text()
if 'includeBuild("build-logic")' not in s:
    s, n = re.subn(r"pluginManagement\s*\{\n", 'pluginManagement {\n    includeBuild("build-logic")\n', s, count=1)
    if n != 1:
        sys.exit("android-new: no pluginManagement { } block in settings.gradle.kts")
    settings.write_text(s)
    print("settings: includeBuild(\"build-logic\") added")

(root / "build.gradle.kts").write_text(
    "// Top-level build file. Every module applies an android-forge convention plugin (build-logic/);\n"
    "// android-forge.root loads build-logic once in the root classloader and owns the coverage gate.\n"
    "plugins {\n"
    "    id(\"android-forge.root\")\n"
    "}\n"
)
print("root build.gradle.kts: android-forge.root only")
PY
}

cmd_create() {
    local name="$1" app_id="$2" min_sdk="$3" target="$4"
    require_android
    [[ "$app_id" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]] || die "invalid application id: $app_id"
    [[ "$min_sdk" =~ ^[0-9]+$ ]] || die "invalid minSdk: $min_sdk"

    local out="$target"
    if [[ -d "$target" && -n "$(ls -A "$target" 2>/dev/null)" ]]; then
        out="$target.android-create"
        rm -rf "$out"
    fi

    if ! android create empty-activity --name="$name" --application-id="$app_id" --namespace="$app_id" \
        --min-sdk="$min_sdk" --output="$out"; then
        echo "android-new: 'android create' failed" >&2
        exit 2
    fi

    if [[ "$out" != "$target" ]]; then
        # Never overwrite what the user already has in the target directory.
        cp -Rn "$out/." "$target/"
        rm -rf "$out"
        echo "merged into existing $target without overwriting existing files"
    fi

    cmd_prepare "$target" "$min_sdk"
}

main() {
    [[ $# -ge 1 ]] || die "usage: $0 <create|prepare|ensure-sdk> ..."
    local cmd="$1"; shift
    case "$cmd" in
        create)     [[ $# -eq 4 ]] || die "create <app-name> <application-id> <min-sdk> <target-dir>"; cmd_create "$@" ;;
        prepare)    [[ $# -eq 2 ]] || die "prepare <target-dir> <min-sdk>"; cmd_prepare "$@" ;;
        ensure-sdk) [[ $# -eq 1 ]] || die "ensure-sdk <compile-sdk>"; cmd_ensure_sdk "$@" ;;
        *)          die "unknown sub-command: $cmd" ;;
    esac
}

main "$@"
