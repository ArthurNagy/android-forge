#!/usr/bin/env bash
#
# android-forge overlay renderer.
#
# Usage:
#   apply-overlay.sh render <src-dir> <dest-dir> [--no-clobber]
#       Walk <src-dir>, render every .tmpl file via envsubst (strips .tmpl suffix),
#       copy non-.tmpl files as-is. Preserves directory structure. --no-clobber keeps any
#       file that already exists at the destination (adopt; never blind-overwrite a project).
#
#   apply-overlay.sh render-module <module-name> <src-dir> <dest-dir> <base-package-path>
#       Same as render but src/<sourceSet>/kotlin/X.kt → dest/src/<sourceSet>/kotlin/<base-package-path>/<module-path>/X.kt
#       for every source set (main, test, androidTest, debug, ...). <module-name> is a package
#       suffix: dots become directories (`core.ui` → core/ui/, `feature.gallery.impl` →
#       feature/gallery/impl/), and an empty string ("") puts files directly in <base-package-path>/
#       (used for :app). Non-Kotlin files (res/, resources/, build files) keep their path.
#
#   apply-overlay.sh patch-settings <project-dir> <module-list>
#       Append `include(":x")` lines to project's settings.gradle.kts for each module
#       in comma-separated <module-list> (`core:ui,feature:gallery:impl`), idempotently.
#
#   apply-overlay.sh patch-libs <project-dir> <additions-toml-file>
#       Merge [versions], [libraries], [plugins] entries from <additions-toml-file> into the
#       project's gradle/libs.versions.toml. Section-aware: appends missing keys under each header
#       (creates the header if missing). A [versions] key that already exists with a LOWER version
#       is raised to the additions' value (android-forge's tested floor) — never downgraded; any
#       other existing key is left as is.
#
#   apply-overlay.sh pin-toolchain <project-dir>
#       Raise the Gradle wrapper to >= MIN_GRADLE (distributionUrl + distributionSha256Sum fetched
#       from services.gradle.org) and the Gradle daemon heap (org.gradle.jvmargs -Xmx) to
#       >= MIN_GRADLE_HEAP_MB (Hilt/KSP + Robolectric need more than `android create`'s 2 GiB).
#       Never downgrades. The AGP/Kotlin versions are catalog keys: patch-libs raises those.
#
# Required env vars when rendering .tmpl files:
#   APP_NAME, BASE_PACKAGE, BASE_PACKAGE_PATH, APP_TAGLINE (optional), MIN_SDK, FORM_FACTORS,
#   BUILD_COMMANDS, MODULE_LIST, FEATURE_LIST, OPTIONAL_LIBS, FIGMA_URL, PROJECT_OVERRIDES,
#   TIMELINE, SCAFFOLD_DATE, SPEC_WORKFLOW. For feature templates: FEATURE_NAME (kebab),
#   FEATURE_NAME_PKG, FEATURE_NAME_CAMEL, FEATURE_NAME_PASCAL, FEATURE_NAME_SNAKE.
#   For form-factor templates: CAR_APP_CATEGORY — the Car App Library category suffix in UPPERCASE (POI, IOT, WEATHER,
#   NAVIGATION, MESSAGING; envsubst can't change case, the add-form-factor export block uppercases it).
#   For autoloop: AUTOLOOP_HANDOFF, READY_APPROVERS, AUTOLOOP_QA.
#   Unset variables substitute as empty strings (envsubst default).

set -euo pipefail

die() { echo "apply-overlay: $*" >&2; exit 1; }

# Only these variables are substituted. A bare `envsubst` replaces EVERY $VAR / ${VAR} in
# the file — including shell variables that templates must keep verbatim, e.g.
# release.yml's `$ANDROID_KEYSTORE_BASE64` / `$RUNNER_TEMP`, which would render as "".
# Adding an overlay variable? Add it here AND to the export block in commands/android-forge-init.md
# (or the add-feature / add-form-factor / add-autoloop export blocks for their templates).
OVERLAY_VARS='${APP_NAME} ${APP_TAGLINE} ${BASE_PACKAGE} ${BASE_PACKAGE_PATH} ${MIN_SDK} ${FORM_FACTORS}
${BUILD_COMMANDS} ${MODULE_LIST} ${FEATURE_LIST} ${OPTIONAL_LIBS} ${FIGMA_URL}
${PROJECT_OVERRIDES} ${TIMELINE} ${SCAFFOLD_DATE} ${SPEC_WORKFLOW}
${FEATURE_NAME} ${FEATURE_NAME_PKG} ${FEATURE_NAME_CAMEL} ${FEATURE_NAME_PASCAL} ${FEATURE_NAME_SNAKE}
${CAR_APP_CATEGORY}
${AUTOLOOP_HANDOFF} ${READY_APPROVERS} ${AUTOLOOP_QA}'

# Toolchain floor applied by pin-toolchain (`android create` may ship an older wrapper).
# /android-forge-bump-stack moves projects beyond it; bump these when the floor itself should rise.
MIN_GRADLE="9.8.1"
MIN_GRADLE_HEAP_MB=4096

require_envsubst() {
    if ! command -v envsubst >/dev/null; then
        die "envsubst not found. Install via 'brew install gettext && brew link --force gettext'."
    fi
}

render_file() {
    local src="$1" dest="$2" no_clobber="${3:-}"
    if [[ -n "$no_clobber" && -e "$dest" ]]; then
        echo "kept existing: $dest"
        return
    fi
    mkdir -p "$(dirname "$dest")"
    if [[ "$src" == *.tmpl ]]; then
        envsubst "$OVERLAY_VARS" < "$src" > "$dest"
    else
        cp "$src" "$dest"
    fi
}

cmd_render() {
    local src_dir="$1" dest_dir="$2" no_clobber=""
    [[ "${3:-}" == "--no-clobber" ]] && no_clobber=1
    [[ -z "${3:-}" || -n "$no_clobber" ]] || die "render: unknown flag $3"
    require_envsubst
    [[ -d "$src_dir" ]] || die "source dir not found: $src_dir"
    mkdir -p "$dest_dir"

    find "$src_dir" -type f | while read -r src_file; do
        local rel="${src_file#$src_dir/}"
        local dest_rel="${rel%.tmpl}"
        local dest_file="$dest_dir/$dest_rel"
        render_file "$src_file" "$dest_file" "$no_clobber"
    done
}

cmd_render_module() {
    local module_name="$1" src_dir="$2" dest_dir="$3" base_pkg_path="$4"
    require_envsubst
    # Module templates are all `package ${BASE_PACKAGE}…`: an unset variable (exports lost
    # between shell sessions) would silently render `package .core.ui` into `src/.../kotlin//core/ui/`.
    [[ -n "${BASE_PACKAGE:-}" ]] || die "BASE_PACKAGE is empty — export the overlay variables first"
    [[ -n "$base_pkg_path" ]] || die "base-package-path is empty"
    [[ -d "$src_dir" ]] || die "source dir not found: $src_dir"
    mkdir -p "$dest_dir"

    # Package suffix → path: `core.ui` → `core/ui/`; "" → no extra segment.
    local pkg_dir="$base_pkg_path"
    [[ -n "$module_name" ]] && pkg_dir="$base_pkg_path/${module_name//.//}"

    find "$src_dir" -type f | while read -r src_file; do
        local rel="${src_file#$src_dir/}"
        local dest_rel
        # Insert the package path after src/<sourceSet>/kotlin/ (any source set)
        if [[ "$rel" =~ ^src/([A-Za-z0-9]+)/kotlin/(.+)$ ]]; then
            local sourceset="${BASH_REMATCH[1]}"
            local tail="${BASH_REMATCH[2]}"
            dest_rel="src/$sourceset/kotlin/$pkg_dir/$tail"
        else
            dest_rel="$rel"
        fi
        dest_rel="${dest_rel%.tmpl}"
        local dest_file="$dest_dir/$dest_rel"
        render_file "$src_file" "$dest_file"
    done
}

cmd_patch_settings() {
    local project_dir="$1" module_csv="$2"
    local settings="$project_dir/settings.gradle.kts"
    [[ -f "$settings" ]] || die "settings.gradle.kts not found at: $settings"

    # Ensure the file ends with a newline before appending — a bare `>>` would otherwise
    # concatenate the first include() onto the last line.
    [[ -s "$settings" && -n "$(tail -c1 "$settings")" ]] && printf '\n' >> "$settings"

    IFS=',' read -ra modules <<< "$module_csv"
    for m in "${modules[@]}"; do
        m="$(echo "$m" | xargs)"  # trim
        [[ -z "$m" ]] && continue
        m="${m#:}"
        local include_line="include(\":$m\")"
        if grep -qxF "$include_line" "$settings"; then
            echo "skip (already present): $include_line"
        else
            echo "$include_line" >> "$settings"
            echo "added: $include_line"
        fi
    done
}

cmd_patch_libs() {
    local project_dir="$1" additions="$2"
    local libs_file="$project_dir/gradle/libs.versions.toml"
    [[ -f "$libs_file" ]] || die "libs.versions.toml not found at: $libs_file"
    [[ -f "$additions" ]] || die "additions file not found: $additions"

    require_envsubst

    local tmp_additions
    tmp_additions="$(mktemp)"
    envsubst "$OVERLAY_VARS" < "$additions" > "$tmp_additions"

    python3 - "$libs_file" "$tmp_additions" <<'PY'
import re, sys, pathlib

libs_path = pathlib.Path(sys.argv[1])
add_path = pathlib.Path(sys.argv[2])
KEY = re.compile(r'^([A-Za-z0-9._-]+|"[^"]+")\s*=')
VERSION = re.compile(r'^(?P<key>[A-Za-z0-9._-]+)\s*=\s*"(?P<v>[^"]+)"\s*(#.*)?$')

def parse_sections(text):
    sections = {None: []}
    current = None
    for line in text.splitlines(keepends=False):
        m = re.match(r"^\[(.+)\]\s*$", line)
        if m:
            current = m.group(1)
            sections.setdefault(current, [])
        else:
            sections.setdefault(current, []).append(line)
    return sections

def key_of(line):
    s = line.strip()
    if not s or s.startswith("#"):
        return None
    m = KEY.match(s)
    return m.group(1).strip('"') if m else None

def vkey(v):
    # Numeric-aware comparison; a pre-release part (alpha01, rc02) sorts below the release.
    parts = []
    for p in re.split(r"[.\-]", v):
        parts.append((1, int(p), "") if p.isdigit() else (0, 0, p))
    return parts

base = parse_sections(libs_path.read_text())
add = parse_sections(add_path.read_text())

# Raise existing [versions] keys to the additions' floor (never downgrade).
floors = {}
for line in add.get("versions", []):
    m = VERSION.match(line.strip())
    if m:
        floors[m.group("key")] = m.group("v")
for i, line in enumerate(base.get("versions", [])):
    m = VERSION.match(line.strip())
    if not m or m.group("key") not in floors:
        continue
    have, floor = m.group("v"), floors[m.group("key")]
    if vkey(have) < vkey(floor):
        base["versions"][i] = line.replace(f'"{have}"', f'"{floor}"', 1)
        print(f"raised: {m.group('key')} {have} -> {floor}")

for section, add_lines in add.items():
    if section is None:
        continue
    base_lines = base.setdefault(section, [])
    have = {k for k in (key_of(l) for l in base_lines) if k}
    appended = []
    for line in add_lines:
        k = key_of(line)
        if k is None:
            # keep comments/blank lines only when they precede something we append
            appended.append(line)
            continue
        if k in have:
            continue
        appended.append(line)
        have.add(k)
    # drop comment/blank runs that ended up with nothing after them
    while appended and key_of(appended[-1]) is None:
        appended.pop()
    if appended:
        if base_lines and base_lines[-1].strip() != "":
            base_lines.append("")
        base_lines.append(f"# --- android-forge additions ({section}) ---")
        base_lines.extend(appended)

out = []
out.extend(base.pop(None, []))
for section, lines in base.items():
    if out and out[-1].strip() != "":
        out.append("")
    out.append(f"[{section}]")
    out.extend(lines)
libs_path.write_text("\n".join(out).rstrip() + "\n")
print(f"patched: {libs_path}")
PY

    rm -f "$tmp_additions"
}

cmd_pin_toolchain() {
    local project_dir="$1"
    local wrapper="$project_dir/gradle/wrapper/gradle-wrapper.properties"
    [[ -f "$wrapper" ]] || die "gradle-wrapper.properties not found at: $wrapper"

    local current_gradle sha=""
    current_gradle="$(sed -nE 's#^distributionUrl=.*gradle-([0-9][0-9.]*)-(bin|all)\.zip.*#\1#p' "$wrapper")"
    if [[ -n "$current_gradle" && "$(printf '%s\n%s\n' "$current_gradle" "$MIN_GRADLE" | sort -V | tail -1)" != "$current_gradle" ]]; then
        sha="$(curl -sfL "https://services.gradle.org/distributions/gradle-${MIN_GRADLE}-bin.zip.sha256" || true)"
        [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || die "could not fetch the sha256 for Gradle $MIN_GRADLE (offline?)"
    fi

    python3 - "$wrapper" "$project_dir/gradle.properties" "$MIN_GRADLE" "$sha" "$MIN_GRADLE_HEAP_MB" <<'PY'
import re, sys, pathlib

wrapper, props = (pathlib.Path(a) for a in sys.argv[1:3])
min_gradle, sha, gradle_heap = sys.argv[3:6]

# 1. Gradle wrapper (sha is only passed when an upgrade is due)
if sha:
    w = wrapper.read_text()
    w = re.sub(r"(?m)^distributionUrl=.*$",
               "distributionUrl=https\\://services.gradle.org/distributions/gradle-%s-bin.zip" % min_gradle, w)
    if re.search(r"(?m)^distributionSha256Sum=", w):
        w = re.sub(r"(?m)^distributionSha256Sum=.*$", "distributionSha256Sum=" + sha, w)
    else:
        w = w.rstrip("\n") + "\ndistributionSha256Sum=" + sha + "\n"
    wrapper.write_text(w)
    print(f"gradle wrapper -> {min_gradle}")
else:
    print(f"gradle wrapper: already >= {min_gradle}")

# 2. Gradle daemon heap
p = props.read_text() if props.exists() else ""
m = re.search(r"(?m)^org\.gradle\.jvmargs=(.*)$", p)
if not m:
    p = p.rstrip("\n") + f"\norg.gradle.jvmargs=-Xmx{gradle_heap}M -Dfile.encoding=UTF-8\n"
    print(f"org.gradle.jvmargs: added -Xmx{gradle_heap}M")
else:
    args = m.group(1)
    x = re.search(r"-Xmx(\d+)([mMgG])", args)
    mb = (int(x.group(1)) * (1024 if x.group(2) in "gG" else 1)) if x else 0
    if mb >= int(gradle_heap):
        print("org.gradle.jvmargs: heap already sufficient")
    else:
        args = (args[:x.start()] + f"-Xmx{gradle_heap}M" + args[x.end():]) if x else f"-Xmx{gradle_heap}M {args}".strip()
        p = p[:m.start(1)] + args + p[m.end(1):]
        print(f"org.gradle.jvmargs: -Xmx raised to {gradle_heap}M")
props.write_text(p)
PY
}

main() {
    [[ $# -ge 1 ]] || die "usage: $0 <render|render-module|patch-settings|patch-libs|pin-toolchain> ..."
    local cmd="$1"; shift
    case "$cmd" in
        render)           [[ $# -eq 2 || $# -eq 3 ]] || die "render <src> <dest> [--no-clobber]"; cmd_render "$@" ;;
        render-module)    [[ $# -eq 4 ]] || die "render-module <module> <src> <dest> <base-pkg-path>"; cmd_render_module "$@" ;;
        patch-settings)   [[ $# -eq 2 ]] || die "patch-settings <project> <module-csv>"; cmd_patch_settings "$@" ;;
        patch-libs)       [[ $# -eq 2 ]] || die "patch-libs <project> <additions-toml>"; cmd_patch_libs "$@" ;;
        pin-toolchain)    [[ $# -eq 1 ]] || die "pin-toolchain <project>"; cmd_pin_toolchain "$@" ;;
        *)                die "unknown sub-command: $cmd" ;;
    esac
}

main "$@"
