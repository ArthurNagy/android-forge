---
description: Scaffold a new Android (Jetpack Compose) project with Google's Android CLI (`android create`) and apply the android-forge overlay — Hilt, Orbit, Nav 3 api/impl features, core modules, CI, product workflow and Android skills.
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

Skip anything the user already stated. Ask 1–2 in a plain message (they are free text); ask 3–10 with
`AskUserQuestion` — at most 4 questions per call and 4 options per question, split as below.

1. **App name** — PascalCase, no spaces (e.g. `Framefit`, `Cadenza`). The project lands in `<parent>/<APP_NAME>`;
   the parent is the current directory unless the user named one (ask when the current directory is itself a project).
2. **Application ID / base package** — reverse-domain, lowercase (e.g. `com.arthurnagy.framefit`).
   The same value is the `applicationId` and the Kotlin base package.
3. **minSdk** — `26` (Recommended: `java.time` and adaptive icons without compat code), `24`, `28`, `29`.
4. **Extra devices** (multi-select; phones, tablets and foldables are always in): Wear OS · TV ·
   Cars · XR. Follow-ups only for what was picked: Cars → *Android Auto*, *Android Automotive OS*,
   or both, plus the app category in two questions (kind: Templated · Media · Parked — video / games / browser;
   Templated → POI · IoT · Weather · Navigation, messaging via "Other"); XR → *headset*, *display/AI glasses*, or both.
5. **Extra surfaces** (multi-select): Googlebook/ChromeOS desktop polish · Google Cast (sender) ·
   home-screen widgets.
6. **Code-wired opt-ins** (multi-select): Network (Retrofit 3 + OkHttp 5 → `:core:network`) ·
   Database (Room 3) · Baseline Profiles + Macrobenchmark (`:benchmarks`).
7. **Notes-only opt-ins** (multi-select; documented, wired later by hand): Firebase Crashlytics ·
   Sentry · Firebase App Distribution · gradle-play-publisher.
8. **License**: MIT (default) / Apache-2.0 / Proprietary.
9. **Initialize git + first commit**: yes (default) / no.
10. **Spec workflow**: **OpenSpec (Recommended)** — spec-driven changes (`/opsx:propose` →
    `/opsx:apply`) with android-forge's project rules, the `spec-link` CI check, and the path the
    autonomous build loop runs on / **Plain docs** — `docs/MVP_SPEC.md` + ADRs only. Either way,
    GitHub issues labeled `ready` are the backlog.

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
export MIN_SDK="<26|24|28|29>"
export SCAFFOLD_DATE="$(date -u +%Y-%m-%d)"
# Markdown bullets, one per form factor: always the adaptive line, plus each selected extra.
export FORM_FACTORS='- Phones, tablets, foldables — one adaptive `:app`
<- Wear OS — `:wear` (own APK, same applicationId) … one line per selection>'
export BUILD_COMMANDS='```bash
./gradlew assembleDebug                      # debug APK(s)
./gradlew unitTests                          # every module'"'"'s local tests (Robolectric included)
./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true   # the CI gate
./gradlew recordRoborazziDebug               # re-record screenshot goldens after an intended UI change
```'
export MODULE_LIST="- :app · :core:{model,domain,data,datastore,designsystem,ui,navigation,testing} · build-logic/<, :core:network><, :benchmarks><, form-factor modules>"
export FEATURE_LIST="_(none yet — add via /android-forge-add-feature)_"
export OPTIONAL_LIBS="<csv of opted-in libs, or '(none)'>"
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
    FORM_FACTORS BUILD_COMMANDS MODULE_LIST FEATURE_LIST OPTIONAL_LIBS FIGMA_URL \
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

# CI workflows (pr.yml, release.yml, spec-link.yml — the latter skips itself without openspec/)
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

# build-logic (convention plugins)
cp -R "${OVERLAY}/build-logic" "${TARGET}/build-logic"

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
  **First table** recipe, which creates `:core:database`. Record "Room 3 (opt-in, created with the
  first table)" in `OPTIONAL_LIBS`.
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

For each extra device or surface from step 1 (in this order: desktop, XR, glasses, widgets, Wear,
TV, Auto, AAOS, Cast), run the `/android-forge-add-form-factor` recipe — i.e. spawn the
`android-forge:android-form-factor-builder` agent with `form_factor`, `project_root` (= `${TARGET}`),
`base_package` (= `${BASE_PACKAGE}`), `claude_plugin_root` (the absolute value of `${CLAUDE_PLUGIN_ROOT}` — the agent
doesn't inherit it) and, for cars, `car_app_category`. It adds the module or manifest pieces, the catalog entries and the
form factor's skill tier; it **asks before** creating an emulator. Run them one at a time — each
edits `settings.gradle.kts` and the catalog.

### 7. Android skills (project-scoped)

Install the baseline tier into the project — committed with it, so every session and the
autonomous loop have them (form-factor tiers were added in step 6):

```bash
source "${TMPDIR:-/tmp}/android-forge-init.env"; : "${TARGET:?}"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" install "${TARGET}" baseline
```

### 8. License

Apache-2.0: replace `LICENSE` with the Apache 2.0 text. Proprietary: a short proprietary notice.
MIT: the MIT text with the current year and the user's name.

### 9. Format, record goldens, verify the gate

The overlay's imports are ordered for a `com.*` package and line wrapping depends on name lengths,
so normalize once, record any screenshot goldens, then run the CI gate exactly as CI will (the first
run downloads dependencies — allow several minutes):

```bash
source "${TMPDIR:-/tmp}/android-forge-init.env"; cd "${TARGET:?}" || exit 1
./gradlew spotlessApply -q 2>&1 | tail -20
./gradlew recordRoborazziDebug -q 2>&1 | tail -20
./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true --console=plain 2>&1 | tail -25
```

A failure here is a scaffold bug: show it verbatim and stop — don't paper over it.

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
gh repo create "<APP_NAME>" --private --source=. --remote=origin
git push -u origin main
bash "${CLAUDE_PLUGIN_ROOT}/scripts/issues.sh" labels   # ready, in-progress, priority:*, no-spec, chore, adr
```

If `gh` is not authenticated, surface `! gh auth login` instead of failing. Never create a public
repo. On a no: print the commands for later.

### 11. Report next steps

```
✓ Project scaffolded at <path> (android create + android-forge overlay)
✓ Modules: :app · :core:{model,domain,data,datastore,designsystem,ui,navigation,testing}<, :core:network><, :benchmarks><, form factors> + build-logic/
✓ Composition root: app/…/MainApplication (Hilt) · MainActivity (Set<EntryProviderInstaller>) · AppNavigation (Nav 3, list-detail scenes) · Home placeholder
✓ Gate green: spotlessCheck lint coverageVerify assembleDebug (Roborazzi verify)
✓ Android skills: baseline<+ form-factor tiers> in .claude/skills/
✓ CI workflows: .github/workflows/pr.yml + release.yml + spec-link.yml
✓ Product docs: docs/MVP_SPEC.md + docs/DECISIONS/{0001..0009}.md
✓ Spec workflow: <OpenSpec | plain docs>
✓ Issue labels: <created | run issues.sh labels after pushing>

Next:
  1. Open in Android Studio, or run it: android emulator start <avd> && android run --apks=app/build/outputs/apk/debug/app-debug.apk
  2. Enable branch protection on main (see https://github.com/arthurnagy/android-forge/blob/main/docs/git-conventions.md)
  3. /android-forge-spec — fill out docs/MVP_SPEC.md
  4. /android-forge-refine --gaps — draft the first backlog issues; approve with: gh issue edit <n…> --add-label ready
  5. /android-forge-add-feature <name> — your first feature (it can take over the start destination)

Notes-only opt-ins: <list + doc links>
```

## Notes

- The plugin never pushes, creates a remote, or enables branch protection without an explicit yes
  in this session.
- `android create`'s template can change between Android CLI releases; `android-new.sh prepare` fails
  loudly when the shape it expects (settings `pluginManagement`, `<application>`) is gone — fix the
  script, don't hand-patch around it.
- `openspec init` writes `.claude/commands/opsx/*` and `.claude/skills/openspec-*`; `skills.sh` writes
  `.claude/skills/<google-skill>/` — all committed with the project.
- If a script errors, surface the error verbatim and stop — do NOT clean up a partially applied
  overlay (let the user inspect).
