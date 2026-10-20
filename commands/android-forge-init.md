---
description: Scaffold a new Android Jetpack Compose app with Google's Android CLI on the android-forge locked stack — Hilt, Orbit, Nav 3, core modules, CI, form factors.
---

# /android-forge-init

End-to-end scaffold for a new pure-Android app on the android-forge locked stack.

## Layout (`android create` output → android-forge overlay)

`android create empty-activity` (Google's Android CLI) generates a single **`:app`** module — a
Compose activity with sample code under `src/*/java`, AGP 9 built-in Kotlin, a version catalog and
a Gradle wrapper. `scripts/android-new.sh` runs it and prepares the output (sample code removed,
backup rules wired, root build reduced to `id("android-forge.root")`, `includeBuild("build-logic")`).
The overlay then adds:

- **build-logic/** — precompiled convention plugins (`android-forge.android.application`,
  `.android.library[.compose]`, `.jvm.library`, `.feature.api`, `.feature.impl`, `.hilt`, `.room`,
  `.spotless`, `.root`) carrying SDK levels, Lint + compose-lints, Spotless/ktlint + compose-rules, JaCoCo and the
  test stack.
- **:core:*** — `model` · `domain` · `data` · `datastore` · `designsystem` · `ui` · `navigation` ·
  `testing` (Google's modularization shape; `:core:network` with the network opt-in).
- **:app** — the composition root: `MainApplication` (`@HiltAndroidApp`), `MainActivity`
  (`@AndroidEntryPoint`, injects every feature's Nav 3 entry builders), `AppNavigation` (the one
  back stack, list-detail scene strategy), a `Home` placeholder, and the theme from the stored
  `ThemeMode` — a working DataStore → repository → use case → ViewModel slice.

Features (`:feature:<name>:api` + `:impl`) come later, from `/android-forge-add-feature`.

## Flow

Execute these steps **in order**. Stop and ask if anything is unclear. The Bash tool may run
**zsh**: always brace variables in commands (`"${FEATURE_NAME}"`, never `"$FEATURE_NAME:api"` — zsh
reads `:a` as a path modifier) and quote every path (it may contain spaces).

### 1. Gather project parameters

Skip anything the user already stated. Free-text answers (1–2) come from a plain message — ask, end your turn,
wait. Fixed choices (3–10) go through `AskUserQuestion`, which takes **at most 4 questions per call and 2–4 options
per question** ("Other" is added automatically): ask them in the calls below.

1. **App name** — PascalCase, no spaces (e.g. `Framefit`, `Cadenza`). The project lands in `<parent>/<APP_NAME>`;
   the parent is the current directory unless the user named one (ask when the current directory is itself a project).
2. **Application ID / base package** — reverse-domain, lowercase (e.g. `com.arthurnagy.framefit`).
   The same value is the `applicationId` and the Kotlin base package.

**Call A** — 3–6:

3. **minSdk** — `29` (Recommended — Android 10) · `31` (Android 12: SplashScreen API, dynamic color) · `33`
   (Android 13: per-app languages, notification permission). android-forge's floor is 29; `java.time` needs no
   desugaring there.
4. **Extra devices** (multi-select; phones, tablets and foldables are always in): Wear OS · TV · Cars · XR.
5. **Extra surfaces** (multi-select): Googlebook/ChromeOS desktop polish · Google Cast (sender) · home-screen widgets.
6. **Code-wired opt-ins** (multi-select): Network (Retrofit 3 + OkHttp 5 → `:core:network`) ·
   Database (Room 3) · Baseline Profiles + Macrobenchmark (`:benchmarks`).

Nothing picked in a multi-select (or "Other: none") = none.

**Call B** — 7–10:

7. **Notes-only opt-ins** (multi-select; documented, wired later by hand): Firebase Crashlytics ·
   Sentry · Firebase App Distribution · gradle-play-publisher.
8. **License**: MIT (Recommended) · Apache-2.0 · Proprietary. MIT and Proprietary name a copyright holder:
   `git config user.name`; when that is empty, ask for the name in a plain message.
9. **Initialize git + first commit**: Yes (Recommended) · No.
10. **Spec workflow**: **OpenSpec (Recommended)** — spec-driven changes (`/opsx:propose` →
    `/opsx:apply`) with android-forge's project rules, the `spec-link` CI check, and the path the
    autonomous build loop runs on / **Plain docs** — `docs/MVP_SPEC.md` + ADRs only. Either way,
    GitHub issues labeled `ready` are the backlog.

**Call C** — follow-ups, only for what call A picked (skip the call when there are none):

- Cars → **Car platforms**: Android Auto · Android Automotive OS · Both.
- Cars → **Car app kind**: Templated (Car App Library) · Media (Media3, no `:car`) · Parked (video / games / browser
  while parked).
- XR → **XR devices**: Headset · Display/AI glasses · Both.

**Call D** — Templated only: **Car app category**: POI · IoT · Weather · Navigation. Templated **messaging** is
Android Auto only: accept it (through "Other") only when Android Automotive OS wasn't picked; with AAOS, say so and
ask again.

### 1b. Preconditions

Run `/android-forge-doctor`'s checks that matter now (or the doctor itself if anything looks off):
the Android CLI is on PATH (`android --version`), `envsubst` and `python3` exist, and the compile SDK
platform is installed:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/android-new.sh" ensure-sdk 37
```

**OpenSpec chosen?** android-forge's project rules (`openspec/config.yaml` with `context` / `rules`
/ `operations`) need **OpenSpec ≥ 1.14** (Node ≥ 20.19 for the npm install):

```bash
v="$(openspec --version 2>/dev/null || true)"
if [[ -n "$v" && "$(printf '%s\n' 1.14.0 "$v" | sort -V | head -1)" == 1.14.0 ]]; then
    echo "✓ openspec $v"
else
    echo "✗ openspec >= 1.14 needed (found: ${v:-none})"
fi
```

If it is missing or older, ask via `AskUserQuestion` whether to install/upgrade it now —
`brew install openspec` / `brew upgrade openspec`, or `npm install -g @fission-ai/openspec@latest` —
or to continue with **Plain docs**. Never install without that answer.

### 2. Export overlay variables

**Shell state does not persist between Bash tool calls.** Write the variables to an env file once and
`source` it at the top of every later Bash block, so no step renders with an empty `BASE_PACKAGE`:

```bash
export TARGET="<parent folder from step 1, default ${PWD}>/<APP_NAME>"
export APP_NAME="<PascalCase name>"
export APP_TAGLINE='<one-liner or empty>'
export BASE_PACKAGE="<reverse-domain>"
export BASE_PACKAGE_PATH="$(echo "${BASE_PACKAGE}" | tr . /)"
export MIN_SDK="<29|31|33>"
export SCAFFOLD_DATE="$(date -u +%Y-%m-%d)"
# Only the adaptive line: each form factor's builder (step 6) appends its own bullet and modules to CLAUDE.md.
export FORM_FACTORS='- Phones, tablets, foldables — one adaptive `:app`'
# Step 6's builders, in this order (a subset of: desktop xr glasses widgets wear tv auto automotive cast), or "".
export EXTRA_FORM_FACTORS="<e.g. wear auto automotive>"
export CAR_CATEGORY="<poi|iot|weather|navigation|messaging|media|parked — cars only, else empty>"
export LICENSE_ID="<MIT|Apache-2.0|Proprietary>"                 # a file under overlay/licenses/
export COPYRIGHT_HOLDER="$(git config user.name)"                # or the name the user gave in step 1
export BUILD_COMMANDS='```bash
./gradlew assembleDebug                      # debug APK(s)
./gradlew unitTests                          # every module'"'"'s local tests (Robolectric included)
./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true   # the CI gate
./gradlew recordRoborazziDebug               # re-record screenshot goldens after an intended UI change
```'
# Init's own modules only — form-factor modules are added by their builder in step 6.
NETWORK="<yes|no — the Network opt-in>" BENCHMARKS="<yes|no — Baseline Profiles + Macrobenchmark>"
MODULE_LIST="- :app · :core:{model,domain,data,datastore,designsystem,ui,navigation,testing}"
if [[ "${NETWORK}" == yes ]]; then MODULE_LIST="${MODULE_LIST} · :core:network"; fi
if [[ "${BENCHMARKS}" == yes ]]; then MODULE_LIST="${MODULE_LIST} · :benchmarks"; fi
export MODULE_LIST="${MODULE_LIST} · build-logic/"
export FEATURE_LIST="_(none yet — add via /android-forge-add-feature)_"
# Comma-separated, or '(none)': "Retrofit 3 + OkHttp 5 (:core:network)", "Room 3 (opt-in, created with the first
# table)", "Baseline Profiles + Macrobenchmark (:benchmarks)", and each notes-only opt-in by name.
export OPTIONAL_LIBS="<…>"
export FIGMA_URL="(none)"
export PROJECT_OVERRIDES=""
export TIMELINE=""
export USE_OPENSPEC="<yes|no>"
if [[ "${USE_OPENSPEC}" == yes ]]; then
export SPEC_WORKFLOW='Work starts as a GitHub issue (forms in `.github/ISSUE_TEMPLATE/`). Open issues labeled `ready`
are the backlog, ordered `priority:high` → unlabeled → `priority:low`. **Only a human applies
`ready`**: Claude may file and refine issues (`/android-forge-refine`) but never approves them.

Behavior changes go through OpenSpec: `/opsx:propose` (naming the issue: `Issue: #<n>`) →
optionally the `android-spec-critic` agent → `/opsx:apply` → a PR whose body says `Fixes #<n>` →
`/opsx:archive` once merged. `openspec/specs/` records what the app does today;
`openspec/config.yaml` holds the spec rules for this project. Direct edits are for non-behavioral
work only (docs, chores, behavior-neutral refactors). The `spec-link` CI check fails a `feat:` PR
that changes production code without an OpenSpec change; the `no-spec` label is the deliberate
escape hatch.'
else
export SPEC_WORKFLOW='Plain docs (OpenSpec not installed): product scope in `docs/MVP_SPEC.md`, decisions in
`docs/DECISIONS/`. Work is tracked as GitHub issues; open issues labeled `ready` are the backlog,
and only a human applies `ready`. Opt into spec-driven changes later (`openspec init --tools claude`
plus the android-forge rules): see product-workflow.md § OpenSpec.'
fi

# Persist for later Bash calls (typeset -p quotes every value safely, in bash and zsh alike).
typeset -p TARGET APP_NAME APP_TAGLINE BASE_PACKAGE BASE_PACKAGE_PATH MIN_SDK SCAFFOLD_DATE \
    FORM_FACTORS EXTRA_FORM_FACTORS CAR_CATEGORY LICENSE_ID COPYRIGHT_HOLDER \
    BUILD_COMMANDS MODULE_LIST FEATURE_LIST OPTIONAL_LIBS FIGMA_URL \
    PROJECT_OVERRIDES TIMELINE USE_OPENSPEC SPEC_WORKFLOW \
    > "${TMPDIR:-/tmp}/android-forge-init.env"
```

Every later Bash block starts with:

```bash
source "${TMPDIR:-/tmp}/android-forge-init.env"
: "${TARGET:?}" "${APP_NAME:?}" "${BASE_PACKAGE:?}" "${BASE_PACKAGE_PATH:?}" "${MIN_SDK:?}"
```

### 3. Create the project with the Android CLI

```bash
source "${TMPDIR:-/tmp}/android-forge-init.env"
: "${TARGET:?}" "${APP_NAME:?}" "${BASE_PACKAGE:?}" "${MIN_SDK:?}"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/android-new.sh" create "${APP_NAME}" "${BASE_PACKAGE}" "${MIN_SDK}" "${TARGET}"
```

If `$TARGET` already holds files (e.g. a `docs/` folder), the script creates into a sibling and
copies over **without overwriting** — back up an existing `CLAUDE.md` before step 4 renders its
own, and merge the two afterward. Exit code 2 = `android create` itself failed: show its output and
stop (run `android update`, then retry).

### 4. Apply the overlay

One Bash call:

```bash
source "${TMPDIR:-/tmp}/android-forge-init.env"
: "${TARGET:?}" "${APP_NAME:?}" "${BASE_PACKAGE:?}" "${BASE_PACKAGE_PATH:?}" "${MIN_SDK:?}"
OVERLAY="${CLAUDE_PLUGIN_ROOT}/overlay"
AO="${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh"

# Root files (CLAUDE.md, .gitignore, .editorconfig, cliff.toml)
bash "${AO}" render "${OVERLAY}/root" "${TARGET}"

# CI workflows — every file in overlay/ci (pr.yml is the gate; spec-link.yml skips itself without openspec/)
bash "${AO}" render "${OVERLAY}/ci" "${TARGET}/.github/workflows"

# Git templates (PR template, issue forms, gitleaks config, pre-commit hook)
mkdir -p "${TARGET}/.github/ISSUE_TEMPLATE"
cp "${OVERLAY}/git/pull_request_template.md" "${TARGET}/.github/pull_request_template.md"
cp "${OVERLAY}/git/ISSUE_TEMPLATE/"*.yml "${TARGET}/.github/ISSUE_TEMPLATE/"
cp "${OVERLAY}/git/.gitleaks.toml" "${TARGET}/.gitleaks.toml"
cp "${OVERLAY}/git/pre-commit-hook.sh" "${TARGET}/.android-forge-pre-commit.sh"
chmod +x "${TARGET}/.android-forge-pre-commit.sh"

# Product docs (MVP_SPEC.md, DECISIONS/)
bash "${AO}" render "${OVERLAY}/product" "${TARGET}/docs"

# OpenSpec (if chosen): openspec/{specs,changes}/ + the /opsx:* commands and skills under .claude/,
# then android-forge's project rules replace the generated openspec/config.yaml stub.
if [[ "${USE_OPENSPEC}" == yes ]]; then
    openspec init --tools claude --no-animation "${TARGET}"
    bash "${AO}" render "${OVERLAY}/openspec" "${TARGET}/openspec"
    ls "${TARGET}/.claude/commands/opsx/propose.md" "${TARGET}/.claude/commands/opsx/apply.md" >/dev/null \
        || echo "✗ /opsx:* commands missing — openspec init did not set up Claude Code"
fi

# build-logic (convention plugins) — copy its contents, so a re-run doesn't nest build-logic/build-logic/
mkdir -p "${TARGET}/build-logic"
cp -R "${OVERLAY}/build-logic/." "${TARGET}/build-logic/"

# Core modules (package <base>.core.<name>)
for m in model domain data datastore designsystem ui navigation testing; do
    bash "${AO}" render-module "core.${m}" "${OVERLAY}/modules/core/${m}" "${TARGET}/core/${m}" "${BASE_PACKAGE_PATH}"
done

# :app composition root — replaces android create's app/build.gradle.kts and strings.xml on purpose
# (known template output; the launcher icons, themes.xml and xml/ backup rules stay).
bash "${AO}" render-module "" "${OVERLAY}/app" "${TARGET}/app" "${BASE_PACKAGE_PATH}"

bash "${AO}" patch-settings "${TARGET}" \
    "core:model,core:domain,core:data,core:datastore,core:designsystem,core:ui,core:navigation,core:testing"

# Catalog: append android-forge's entries and raise android create's older pins to the tested floor
# (AGP 9.4.1, Kotlin 2.4.21, Nav 3 1.2.0, Compose BOM 2026.09.00, …) — never downgrades.
bash "${AO}" patch-libs "${TARGET}" "${OVERLAY}/gradle/libs.versions.toml.additions.tmpl"

# Gradle wrapper >= 9.8.1 and a 4 GiB daemon heap (Hilt/KSP + Robolectric).
bash "${AO}" pin-toolchain "${TARGET}"
```

### 5. Code-wired opt-ins

- **Network** — render `:core:network` (Hilt `NetworkModule`: one `OkHttpClient`, kotlinx-serialization
  `Json`, `Retrofit` on `BuildConfig.API_BASE_URL`; the `catchNetwork { }` boundary + tests), include
  it, let `:core:data` use it, and grant `INTERNET`:
  ```bash
  source "${TMPDIR:-/tmp}/android-forge-init.env"; : "${TARGET:?}" "${BASE_PACKAGE_PATH:?}"
  AO="${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh"
  bash "${AO}" render-module core.network "${CLAUDE_PLUGIN_ROOT}/overlay/optional/network" "${TARGET}/core/network" "${BASE_PACKAGE_PATH}"
  bash "${AO}" patch-settings "${TARGET}" "core:network"
  ```
  Then with the Edit tool: in `core/data/build.gradle.kts` add `implementation(project(":core:network"))`
  above the `// android-forge:core-data-deps` marker; in `app/src/main/AndroidManifest.xml` add
  `<uses-permission android:name="android.permission.INTERNET" />` above `<application`. Tell the
  user to set the real base URL in `core/network/build.gradle.kts` (`API_BASE_URL`).
- **Database (Room 3)** — nothing to render yet: Room needs at least one entity, and the convention
  (`android-forge.room`: KSP, `androidx.room3`, bundled SQLite, exported schemas) plus the catalog
  entries are already in place. The first slice that persists data runs the `data-layer` skill's
  **First table** recipe, which creates `:core:database`. (Step 2 already listed "Room 3 (opt-in, created with the
  first table)" in `OPTIONAL_LIBS`, so CLAUDE.md says so.)
- **Baseline Profiles + Macrobenchmark** — render `:benchmarks` and wire `:app` to it:
  ```bash
  source "${TMPDIR:-/tmp}/android-forge-init.env"; : "${TARGET:?}" "${BASE_PACKAGE_PATH:?}"
  AO="${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh"
  bash "${AO}" render-module benchmarks "${CLAUDE_PLUGIN_ROOT}/overlay/optional/benchmarks" "${TARGET}/benchmarks" "${BASE_PACKAGE_PATH}"
  bash "${AO}" patch-settings "${TARGET}" "benchmarks"
  ```
  Then in `app/build.gradle.kts`: add `id("androidx.baselineprofile")` to `plugins { }`, and to
  `dependencies { }` add `implementation(libs.androidx.profileinstaller)` and
  `baselineProfile(project(":benchmarks"))`.
- **Notes-only opt-ins** (Crashlytics, Sentry, Firebase App Distribution, gradle-play-publisher):
  nothing is wired — list them in the report with their docs
  (https://github.com/arthurnagy/android-forge/blob/main/docs/observability.md,
  https://github.com/arthurnagy/android-forge/blob/main/docs/release.md); each needs secrets or console setup only
  the user can do.

### 6. Form factors

Skip this step when `EXTRA_FORM_FACTORS` is empty. Print the hand-off values:

```bash
source "${TMPDIR:-/tmp}/android-forge-init.env"; : "${TARGET:?}" "${BASE_PACKAGE:?}" "${APP_NAME:?}"
printf 'form_factors: %s\nproject_root: %s\nbase_package: %s\napp_name: %s\ncar_app_category: %s\n' \
    "${EXTRA_FORM_FACTORS}" "${TARGET}" "${BASE_PACKAGE}" "${APP_NAME}" "${CAR_CATEGORY:--}"
```

Then, for each value in `form_factors`, in that order, run the `/android-forge-add-form-factor` recipe — spawn the
`android-forge:android-form-factor-builder` agent with `form_factor` (Wear OS → `wear`, TV → `tv`, Android Auto →
`auto`, Android Automotive OS → `automotive`, XR headset → `xr`, display/AI glasses → `glasses`, desktop → `desktop`,
Cast → `cast`, widgets → `widgets`), `project_root`, `base_package`, `app_name` (the printed values),
`claude_plugin_root` (the absolute value of `${CLAUDE_PLUGIN_ROOT}` — the agent doesn't inherit it), `gate: skip`
(step 9 formats, records every golden and runs the gate once for the whole project) and, for `auto` /
`automotive`, `car_app_category` (the same for both; the second run reuses `:car`). Run them one at a time — each
edits `settings.gradle.kts`, the catalog and `CLAUDE.md`. The builder decides "already present" from the project
itself and appends its own `## Form factors` bullet and `## Modules` entries — step 4 rendered only the adaptive
line, so don't add them yourself. It renders the module or manifest pieces, the catalog entries and the form
factor's skill tier; a failed builder stops init — show its report verbatim.

**Emulators** — the builders never create one. Of the picks, `desktop`, `xr`, `glasses`, `wear`, `tv` and
`automotive` have an emulator (`widgets` runs on the phone; Android Auto runs in the Desktop Head Unit — print the
steps from `${CLAUDE_PLUGIN_ROOT}/docs/form-factors/cars.md`; Cast needs a real device). Ask via `AskUserQuestion`
which to create now — multi-select, 2–4 options per question (two questions for five or six; a single candidate is
a Create now · Skip question); each downloads a system image, often 1–4 GB. The glasses AVD runs paired with a host phone AVD, which Android Studio's Pairing
Assistant sets up — print the steps from `${CLAUDE_PLUGIN_ROOT}/docs/form-factors/glasses.md`. For the picked ones:

```bash
for ff in <picked: desktop xr glasses wear tv automotive>; do
    bash "${CLAUDE_PLUGIN_ROOT}/scripts/avd.sh" ensure "${ff}" || echo "✗ emulator for ${ff} — see the output above"
done
```

### 7. Android skills (project-scoped)

Install the baseline tier into the project — committed with it, so every session and the
autonomous loop have them (form-factor tiers were added in step 6):

```bash
source "${TMPDIR:-/tmp}/android-forge-init.env"; : "${TARGET:?}"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" install "${TARGET}" baseline
```

### 8. License

The canonical texts ship with the plugin (`overlay/licenses/`) — never write a license from memory. MIT and
Proprietary get the year and the holder; Apache-2.0 is copied verbatim (its appendix's `[yyyy]` /
`[name of copyright owner]` are the per-file notice template, left as is):

```bash
source "${TMPDIR:-/tmp}/android-forge-init.env"; : "${TARGET:?}" "${LICENSE_ID:?}"
[[ "${LICENSE_ID}" == Apache-2.0 || -n "${COPYRIGHT_HOLDER}" ]] || { echo "✗ no copyright holder — ask for it"; exit 1; }
HOLDER="$(printf '%s' "${COPYRIGHT_HOLDER}" | sed 's/[\/&]/\\&/g')"     # escaped for the sed replacement
sed -e "s/\[year\]/$(date +%Y)/" -e "s/\[fullname\]/${HOLDER}/" \
    "${CLAUDE_PLUGIN_ROOT}/overlay/licenses/${LICENSE_ID}.txt" > "${TARGET}/LICENSE"
head -3 "${TARGET}/LICENSE"
```

### 9. Format, record goldens, verify the gate

The overlay's imports are ordered for a `com.*` package and line wrapping depends on name lengths,
so normalize once, record any screenshot goldens, then run the CI gate exactly as CI will. Each Gradle run is its
own Bash call (timeout 600000 — the first run downloads dependencies); the log keeps the full output, the exit code
is Gradle's:

```bash
source "${TMPDIR:-/tmp}/android-forge-init.env"; cd "${TARGET:?}" || exit 1; LOG="${TMPDIR:-/tmp}/android-forge-init-gradle.log"
./gradlew spotlessApply --console=plain > "${LOG}" 2>&1; rc=$?; tail -20 "${LOG}"; echo "exit=${rc}"
```

`exit=0` → the same block with `recordRoborazziDebug`, then with the gate,
`spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true` (`tail -40`). Stop at the first
non-zero exit: it is a scaffold bug — show the tail (and `grep -n "What went wrong" -A15 "${LOG}"`) verbatim, don't
paper over it.

### 10. Git init + first commit + optional GitHub repo

If the user opted into git:

```bash
source "${TMPDIR:-/tmp}/android-forge-init.env"; cd "${TARGET:?}" || exit 1
git init -q -b main
mkdir -p .git/hooks
cp .android-forge-pre-commit.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
git add -A
git commit -q -m "chore: scaffold project via android-forge"
```

Then ask via `AskUserQuestion` whether to **create the GitHub repo and push now** (default: yes,
private). Only on an explicit yes:

```bash
source "${TMPDIR:-/tmp}/android-forge-init.env"; cd "${TARGET:?}" || exit 1
gh repo create "${APP_NAME}" --private --source=. --remote=origin && git push -u origin main \
    && bash "${CLAUDE_PLUGIN_ROOT}/scripts/issues.sh" labels   # ready, in-progress, priority:*, no-spec, chore, adr
```

If `gh` is not authenticated, surface `! gh auth login` instead of failing. Never create a public
repo. On a no: print the commands for later.

### 11. Report next steps

Leave out the push item (2) when step 10 created and pushed the repo; when the user declined git, it starts with
`git init -b main && git add -A && git commit -m "chore: scaffold project via android-forge"`.

```
✓ Project scaffolded at <path> (android create + android-forge overlay)
✓ Modules: :app · :core:{model,domain,data,datastore,designsystem,ui,navigation,testing}<, :core:network><, :benchmarks><, form-factor modules> + build-logic/
✓ Composition root: app/…/MainApplication (Hilt) · MainActivity (Set<EntryProviderInstaller>) · AppNavigation (Nav 3, list-detail scenes) · Home placeholder
✓ Form factors: <each builder's one-line result, or "phones/tablets/foldables only">; emulators: <created | skipped>
✓ Gate green: spotlessCheck lint coverageVerify assembleDebug (Roborazzi verify)
✓ Android skills: baseline<+ form-factor tiers> in .claude/skills/
✓ CI workflows: .github/workflows/<every file rendered from overlay/ci>
✓ Product docs: docs/MVP_SPEC.md + docs/DECISIONS/{0001..0009}.md · LICENSE: <MIT | Apache-2.0 | Proprietary>
✓ Spec workflow: <OpenSpec | plain docs>
✓ Issue labels: <created | run issues.sh labels after pushing>

Next:
  1. Open in Android Studio, or run it: android emulator start <avd> && android run --apks=app/build/outputs/apk/debug/app-debug.apk
  2. Push: gh repo create <APP_NAME> --private --source=. --remote=origin && git push -u origin main, then bash <plugin>/scripts/issues.sh labels
  3. Protect main — require a PR and the "PR / gate" check: https://github.com/arthurnagy/android-forge/blob/main/docs/ci.md#branch-protection
     Running the autonomous loop later (/android-forge-add-autoloop)? Its bookkeeping pushes to main need a bypass for
     the account gh uses — see https://github.com/arthurnagy/android-forge/blob/main/docs/autoloop.md#branch-protection
  4. /android-forge-spec — fill out docs/MVP_SPEC.md
  5. /android-forge-refine --gaps — draft the first backlog issues; approve with: gh issue edit <n…> --add-label ready
  6. /android-forge-add-feature <name> — your first feature (it can take over the start destination)

Notes-only opt-ins: <list + doc links>
```

## Notes

- The plugin never pushes or creates a remote without an explicit yes in this session (step 10's question), and
  never enables branch protection — the user sets it up.
- `android create`'s template can change between Android CLI releases; `android-new.sh prepare` fails
  loudly when the shape it expects (settings `pluginManagement`, `<application>`) is gone — fix the
  script, don't hand-patch around it.
- `openspec init` writes `.claude/commands/opsx/*` and `.claude/skills/openspec-*`; `skills.sh` writes
  `.claude/skills/<google-skill>/` — all committed with the project.
- If a script errors, surface the error verbatim and stop — do NOT clean up a partially applied
  overlay (let the user inspect).
