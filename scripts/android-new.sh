#!/usr/bin/env bash
#
# Create a new Android project with Google's Android CLI (`android create`) and prepare it for the
# android-forge overlay. Used by /android-forge-init.
#
# Usage:
#   android-new.sh create <app-name> <application-id> <min-sdk> <target-dir>
#       Run `android create empty-activity` into <target-dir> (or, when <target-dir> already has
#       files, into "<target-dir>.android-create" and copy over WITHOUT overwriting anything — the
#       merge is verified before the sibling is deleted), then `prepare` it.
#       <min-sdk>: android-forge's default is 29; at least 26 (java.time without desugaring).
#       `android create` also installs platforms/android-36, its template's compileSdk — the CLI has
#       no option to change it; the conventions compile against the catalog's SDK (ensure-sdk).
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

MIN_SDK_FLOOR=26

require_min_sdk() {
    [[ "$1" =~ ^[0-9]+$ ]] || die "invalid minSdk: '$1' (an API level; android-forge's default is 29)"
    [[ "$1" -ge "$MIN_SDK_FLOOR" ]] \
        || die "minSdk $1 is below ${MIN_SDK_FLOOR}: java.time needs 26 without desugaring (android-forge's default is 29)"
}

# Copy <src>'s tree into <dst> without replacing anything already there — portable (`cp -n` exits 1 on
# BSD and on GNU coreutils >= 9.2 when it skips a file, aborting under `set -e`). Verifies the merge:
# every path of <src> exists in <dst> afterwards.
merge_no_clobber() {
    local src="$1" dst="$2" rel kept=0
    while IFS= read -r -d '' rel; do
        rel="${rel#./}"
        if [[ -d "$src/$rel" && ! -L "$src/$rel" ]]; then
            [[ -d "$dst/$rel" ]] || mkdir -p "$dst/$rel"
        elif [[ -e "$dst/$rel" || -L "$dst/$rel" ]]; then
            echo "kept existing: $rel"
            kept=$((kept + 1))
        else
            cp -pR "$src/$rel" "$dst/$rel"   # -R copies a symlink as a symlink (BSD and GNU)
        fi
    done < <(cd "$src" && find . -mindepth 1 -print0)
    while IFS= read -r -d '' rel; do
        rel="${rel#./}"
        [[ -e "$dst/$rel" || -L "$dst/$rel" ]] || die "merge incomplete: $dst/$rel is missing (left $src for inspection)"
    done < <(cd "$src" && find . -mindepth 1 -print0)
    echo "merged into existing $dst ($kept existing file(s) kept)"
}

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
    require_min_sdk "$min_sdk"
    [[ -f "$target/settings.gradle.kts" && -d "$target/app" ]] || die "not an android create project: $target"

    for set in main test androidTest; do
        rm -rf "$target/app/src/$set/java"
    done

    # minSdk >= 26 always holds (require_min_sdk): the -v26 qualifier is obsolete. A file already in
    # mipmap-anydpi (a re-run) wins over the template's -v26 copy.
    local res="$target/app/src/main/res" f
    if [[ -d "$res/mipmap-anydpi-v26" ]]; then
        mkdir -p "$res/mipmap-anydpi"
        for f in "$res/mipmap-anydpi-v26/"*; do
            [[ -e "$f" ]] || continue
            if [[ -e "$res/mipmap-anydpi/${f##*/}" ]]; then rm -f "$f"; else mv "$f" "$res/mipmap-anydpi/"; fi
        done
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
    require_min_sdk "$min_sdk"
    target="${target%/}"
    [[ -n "$target" ]] || die "target dir is empty"

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
        merge_no_clobber "$out" "$target"
        rm -rf "$out"
    fi

    cmd_prepare "$target" "$min_sdk"
}

main() {
    [[ $# -ge 1 ]] || die "usage: $0 <create|prepare|ensure-sdk> ..."
    local cmd="$1"; shift
    case "$cmd" in
        create)     [[ $# -eq 4 ]] || die "create <app-name> <application-id> <min-sdk (default 29, >= 26)> <target-dir>"; cmd_create "$@" ;;
        prepare)    [[ $# -eq 2 ]] || die "prepare <target-dir> <min-sdk (>= 26)>"; cmd_prepare "$@" ;;
        ensure-sdk) [[ $# -eq 1 ]] || die "ensure-sdk <compile-sdk>"; cmd_ensure_sdk "$@" ;;
        *)          die "unknown sub-command: $cmd" ;;
    esac
}

main "$@"
