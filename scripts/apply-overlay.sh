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
#       (creates the header if missing); a multi-line array value moves as one entry. A [versions]
#       key that already exists with a LOWER version (or an empty one) is raised to the additions'
#       value (android-forge's tested floor) — never downgraded; any other existing key is left as is.
#       Ordering: 1.0.0 > 1.0.0-rc01 > 1.0.0-beta02 > 1.0.0-alpha01, numeric parts numerically.
#       The core additions reference ${MIN_SDK}: export it (the project's minSdk) or patch-libs refuses.
#
#   apply-overlay.sh pin-toolchain <project-dir>
#       Raise the Gradle wrapper to >= MIN_GRADLE (distributionUrl + distributionSha256Sum fetched
#       from services.gradle.org) and the Gradle daemon heap (org.gradle.jvmargs -Xmx) to
#       >= MIN_GRADLE_HEAP_MB (Hilt/KSP + Robolectric need more than `android create`'s 2 GiB).
#       Never downgrades. The AGP/Kotlin versions are catalog keys: patch-libs raises those.
#
# Overlay variables (env) that .tmpl files render:
#   APP_NAME, BASE_PACKAGE, BASE_PACKAGE_PATH, APP_TAGLINE (optional), MIN_SDK, FORM_FACTORS,
#   BUILD_COMMANDS, MODULE_LIST, FEATURE_LIST, OPTIONAL_LIBS, FIGMA_URL, PROJECT_OVERRIDES,
#   TIMELINE, SCAFFOLD_DATE, SPEC_WORKFLOW. For feature templates: FEATURE_NAME (kebab),
#   FEATURE_NAME_PKG, FEATURE_NAME_CAMEL, FEATURE_NAME_PASCAL, FEATURE_NAME_SNAKE.
#   For form-factor templates: CAR_APP_CATEGORY — the Car App Library category suffix in UPPERCASE (POI, IOT, WEATHER,
#   NAVIGATION, MESSAGING; envsubst can't change case, the add-form-factor export block uppercases it).
#   For autoloop: AUTOLOOP_HANDOFF, READY_APPROVERS, AUTOLOOP_QA.
#   Unset variables substitute as empty strings (envsubst default) — except REQUIRED_VARS below:
#   render / render-module / patch-libs refuse (before writing anything) when a template they are about
#   to render references one of those and it is empty (exports lost between shell sessions), and when
#   MIN_SDK isn't an integer or CAR_APP_CATEGORY isn't one of the Car App Library categories.

set -euo pipefail

die() { echo "apply-overlay: $*" >&2; exit 1; }

# Only these variables are substituted. A bare `envsubst` replaces EVERY $VAR / ${VAR} in
# the file — including shell variables that templates must keep verbatim, e.g.
# release.yml's `$ANDROID_KEYSTORE_BASE64` / `$RUNNER_TEMP`, which would render as "".
# Adding an overlay variable? Add it here AND to the export block in commands/android-forge-init.md
# (or the add-feature / add-form-factor / add-autoloop export blocks for their templates).
# shellcheck disable=SC2016 # literal ${VAR} names for envsubst
OVERLAY_VARS='${APP_NAME} ${APP_TAGLINE} ${BASE_PACKAGE} ${BASE_PACKAGE_PATH} ${MIN_SDK} ${FORM_FACTORS}
${BUILD_COMMANDS} ${MODULE_LIST} ${FEATURE_LIST} ${OPTIONAL_LIBS} ${FIGMA_URL}
${PROJECT_OVERRIDES} ${TIMELINE} ${SCAFFOLD_DATE} ${SPEC_WORKFLOW}
${FEATURE_NAME} ${FEATURE_NAME_PKG} ${FEATURE_NAME_CAMEL} ${FEATURE_NAME_PASCAL} ${FEATURE_NAME_SNAKE}
${CAR_APP_CATEGORY}
${AUTOLOOP_HANDOFF} ${READY_APPROVERS} ${AUTOLOOP_QA}'

# Variables a template may never render empty (an empty package, app name or manifest category still
# compiles — and ships broken). The others (APP_TAGLINE, FIGMA_URL, PROJECT_OVERRIDES, TIMELINE, …) may be "".
REQUIRED_VARS="BASE_PACKAGE APP_NAME MIN_SDK CAR_APP_CATEGORY FEATURE_NAME FEATURE_NAME_PKG
FEATURE_NAME_PASCAL FEATURE_NAME_CAMEL FEATURE_NAME_SNAKE"
CAR_APP_CATEGORIES="POI IOT WEATHER NAVIGATION MESSAGING"

# Toolchain floor applied by pin-toolchain (`android create` may ship an older wrapper).
# /android-forge-bump-stack moves projects beyond it; bump these when the floor itself should rise.
MIN_GRADLE="9.8.1"
MIN_GRADLE_HEAP_MB=4096

require_envsubst() {
    if ! command -v envsubst >/dev/null; then
        die "envsubst not found. Install via 'brew install gettext && brew link --force gettext'."
    fi
}

# Strip trailing slashes ("overlay/ci/" → "overlay/ci"): the source prefix is cut off every path
# `find` prints, and a leftover slash would write to <dest>/<whole source path>/….
trim_slash() {
    local p="$1"
    while [[ "$p" == */ && "$p" != / ]]; do p="${p%/}"; done
    printf '%s' "$p"
}

# Die when <file> references a REQUIRED_VARS variable that is empty, or one whose value can't be right.
check_required() {
    local file="$1" v val hint
    for v in $REQUIRED_VARS; do
        # shellcheck disable=SC2016 # matches a literal ${VAR} / $VAR reference
        grep -qE '\$(\{'"${v}"'\}|'"${v}"'([^A-Za-z0-9_]|$))' "$file" || continue
        val="${!v:-}"
        if [[ -z "$val" ]]; then
            hint="export the overlay variables first (source the recipe's env file)"
            [[ "$v" == MIN_SDK ]] && hint="export MIN_SDK=<the project's minSdk, e.g. 29>"
            die "${v} is empty but ${file} needs it — ${hint}"
        fi
        case "$v" in
            MIN_SDK) [[ "$val" =~ ^[0-9]+$ ]] || die "MIN_SDK must be an API level (an integer), got: ${val}" ;;
            CAR_APP_CATEGORY)
                [[ "$val" =~ ^(${CAR_APP_CATEGORIES// /|})$ ]] \
                    || die "CAR_APP_CATEGORY must be one of: ${CAR_APP_CATEGORIES} (uppercase), got: ${val}" ;;
        esac
    done
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
    local src_dir dest_dir no_clobber="" src_file rel dest_file
    src_dir="$(trim_slash "$1")"; dest_dir="$(trim_slash "$2")"
    [[ "${3:-}" == "--no-clobber" ]] && no_clobber=1
    [[ -z "${3:-}" || -n "$no_clobber" ]] || die "render: unknown flag $3"
    require_envsubst
    [[ -d "$src_dir" ]] || die "source dir not found: $src_dir"

    # Every template that will be written has its required values — checked before writing anything.
    while IFS= read -r src_file; do
        rel="${src_file#"$src_dir"/}"
        [[ -n "$no_clobber" && -e "$dest_dir/${rel%.tmpl}" ]] && continue
        check_required "$src_file"
    done < <(find "$src_dir" -type f -name '*.tmpl')

    mkdir -p "$dest_dir"
    while IFS= read -r src_file; do
        rel="${src_file#"$src_dir"/}"
        dest_file="$dest_dir/${rel%.tmpl}"
        render_file "$src_file" "$dest_file" "$no_clobber"
    done < <(find "$src_dir" -type f)
}

cmd_render_module() {
    local module_name="$1" src_dir dest_dir base_pkg_path="$4" src_file rel
    src_dir="$(trim_slash "$2")"; dest_dir="$(trim_slash "$3")"
    require_envsubst
    # Module templates are all `package ${BASE_PACKAGE}…`: an unset variable (exports lost
    # between shell sessions) would silently render `package .core.ui` into `src/.../kotlin//core/ui/`.
    [[ -n "${BASE_PACKAGE:-}" ]] || die "BASE_PACKAGE is empty — export the overlay variables first"
    [[ -n "$base_pkg_path" ]] || die "base-package-path is empty"
    [[ -d "$src_dir" ]] || die "source dir not found: $src_dir"
    while IFS= read -r src_file; do
        check_required "$src_file"
    done < <(find "$src_dir" -type f -name '*.tmpl')
    mkdir -p "$dest_dir"

    # Package suffix → path: `core.ui` → `core/ui/`; "" → no extra segment.
    local pkg_dir="$base_pkg_path"
    [[ -n "$module_name" ]] && pkg_dir="$base_pkg_path/${module_name//.//}"

    while IFS= read -r src_file; do
        rel="${src_file#"$src_dir"/}"
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
        render_file "$src_file" "$dest_dir/$dest_rel"
    done < <(find "$src_dir" -type f)
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
    # The core additions carry `androidMinSdk = "${MIN_SDK}"`: refuse rather than write an empty floor.
    check_required "$additions"

    local tmp_additions rc=0
    tmp_additions="$(mktemp)"
    envsubst "$OVERLAY_VARS" < "$additions" > "$tmp_additions"

    python3 - "$libs_file" "$tmp_additions" "$additions" <<'PY' || rc=$?
import re, sys, pathlib

libs_path = pathlib.Path(sys.argv[1])
add_path = pathlib.Path(sys.argv[2])
add_name = sys.argv[3]
KEY = re.compile(r'^([A-Za-z0-9._-]+|"[^"]+")\s*=')
VERSION = re.compile(r'^(?P<key>[A-Za-z0-9._-]+)\s*=\s*"(?P<v>[^"]*)"\s*(#.*)?$')
HEADER = re.compile(r"^\[(.+)\]\s*$")

def die(msg):
    sys.exit(f"apply-overlay: patch-libs: {msg}")

def depth(s):
    # Net [ / { nesting of one line, ignoring brackets inside strings and comments.
    d, quote, i = 0, None, 0
    while i < len(s):
        c = s[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "#":
            break
        elif c in "[{":
            d += 1
        elif c in "]}":
            d -= 1
        i += 1
    return d

def parse_sections(text, name):
    # {section: [(key | None, [lines])]}: one item per entry — every line of a multi-line array
    # value belongs to its key's entry — or per comment / blank line (key None).
    sections = {None: []}
    current = None
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        h = HEADER.match(line)
        if h:
            current = h.group(1)
            sections.setdefault(current, [])
            continue
        s = line.strip()
        m = KEY.match(s) if s and not s.startswith("#") else None
        if not m:
            sections.setdefault(current, []).append((None, [line]))
            continue
        key = m.group(1).strip('"')
        if '"""' in line or "'''" in line:
            die(f"{name}: multi-line string values aren't supported ({key})")
        entry, d = [line], depth(s[m.end():])
        while d > 0:
            if i >= len(lines):
                die(f"{name}: the value of {key} is never closed")
            entry.append(lines[i])
            d += depth(lines[i])
            i += 1
        sections.setdefault(current, []).append((key, entry))
    return sections

QUALIFIERS = {"alpha": 1, "a": 1, "beta": 2, "b": 2, "milestone": 3, "m": 3, "rc": 4, "cr": 4}

def vkey(v):
    # 1.0.0 > 1.0.0-rc01 > 1.0.0-beta02 > 1.0.0-alpha01 > 1.0.0-dev/-SNAPSHOT (unknown qualifiers);
    # numbers compare numerically, trailing zeros of the release part don't count (1.0 == 1.0.0), and
    # a numeric suffix (KSP's old 2.1.0-1.0.29) ranks above the bare release.
    tokens = re.findall(r"\d+|[a-z]+", v.lower())
    n = 0
    while n < len(tokens) and tokens[n].isdigit():
        n += 1
    release = [int(t) for t in tokens[:n]]
    while release and release[-1] == 0:
        release.pop()
    key = [(2, x) for x in release]
    key += [(2, int(t)) if t.isdigit() else (0, QUALIFIERS.get(t, 0)) for t in tokens[n:]]
    return key + [(1, 0)]  # end marker: above any qualifier, below any further number

def flat(items):
    return [line for _, entry in items for line in entry]

base = parse_sections(libs_path.read_text(), str(libs_path))
add = parse_sections(add_path.read_text(), add_name)

# Raise existing [versions] keys to the additions' floor (never downgrade); fill empty ones.
floors = {}
for key, entry in add.get("versions", []):
    m = VERSION.match(entry[0].strip()) if key and len(entry) == 1 else None
    if m:
        if not m.group("v"):
            die(f"{add_name}: [versions] {key} renders empty — export the overlay variable it uses")
        floors[key] = m.group("v")
versions = base.get("versions", [])
for i, (key, entry) in enumerate(versions):
    m = VERSION.match(entry[0].strip()) if key in floors and len(entry) == 1 else None
    if not m:
        continue
    have, floor = m.group("v"), floors[key]
    if not have:
        line = re.sub(r'=(\s*)""', lambda g: f'={g.group(1)}"{floor}"', entry[0], count=1)
        print(f'repaired: {key} "" -> {floor}')
    elif vkey(have) < vkey(floor):
        line = entry[0].replace(f'"{have}"', f'"{floor}"', 1)
        print(f"raised: {key} {have} -> {floor}")
    else:
        continue
    versions[i] = (key, [line])

for section, add_items in add.items():
    if section is None:
        continue
    base_items = base.setdefault(section, [])
    have = {k for k, _ in base_items if k}
    appended, pending = [], []
    for key, entry in add_items:
        if key is None:
            pending.extend(entry)  # comments / blank lines travel with the entry after them
            continue
        if key not in have:
            appended += pending + entry
            have.add(key)
        pending = []
    while appended and not appended[0].strip():
        appended.pop(0)
    if appended:
        if base_items and flat(base_items)[-1].strip() != "":
            base_items.append((None, [""]))
        base_items.append((None, [f"# --- android-forge additions ({section}) ---"]))
        base_items.append((None, appended))

out = flat(base.pop(None, []))
for section, items in base.items():
    if out and out[-1].strip() != "":
        out.append("")
    out.append(f"[{section}]")
    out.extend(flat(items))
libs_path.write_text("\n".join(out).rstrip() + "\n")
print(f"patched: {libs_path}")
PY

    rm -f "$tmp_additions"
    [[ "$rc" -eq 0 ]] || exit "$rc"
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
