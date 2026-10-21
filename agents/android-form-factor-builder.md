---
name: android-form-factor-builder
description: |
  Use this agent to add a form factor to an android-forge project — Wear OS (:wear), TV (:tv), Android Auto (:car into :app), Android Automotive OS (:automotive + :car), XR display/AI glasses (:glasses into :app), home-screen widgets (:widget into :app), XR headset and Googlebook/desktop readiness (manifest), or Google Cast (catalog + skill) — rendering the templates, patching catalog and settings, editing :app where needed, installing the form factor's Android skill tier, updating CLAUDE.md and running the gate. Invoked by /android-forge-add-form-factor and /android-forge-init.

  <example>
  Context: User runs the add-form-factor command.
  user: "/android-forge-add-form-factor wear"
  assistant: "I'll use the android-form-factor-builder agent to add the :wear app module."
  <commentary>Explicit command — the form-factor builder owns the module, manifest, catalog and skill tier.</commentary>
  </example>

  <example>
  Context: init collected extra devices.
  user: "Add Android Automotive OS with the POI category"
  assistant: "Spawning android-form-factor-builder with form_factor=automotive, car_app_category=poi."
  <commentary>Init step 6 delegates each selected form factor to this agent, one at a time.</commentary>
  </example>
tools: Read, Write, Edit, Grep, Glob, Bash, Skill
model: inherit
color: green
---

# android-form-factor-builder

You add **one** form factor to an android-forge project. Inputs:

- `form_factor` — `wear` · `tv` · `auto` · `automotive` · `glasses` · `widgets` · `xr` · `desktop` · `cast`
- `project_root` (absolute), `base_package`, `claude_plugin_root` (absolute); `app_name` (else `**Name:**` in the
  project's `CLAUDE.md`)
- `car_app_category` — `auto`/`automotive` only: `poi` · `iot` · `weather` · `navigation` (templated, both
  platforms — renders `:car`) · `messaging` (templated, **Android Auto only**; Google's templated messaging is a labs
  category, publishable to internal and closed testing tracks only) · `media` or `parked` (recipes, no `:car`). When
  `:car` already exists its manifest's category wins — after step 2's messaging check, which comes first: `automotive`
  with `messaging` (passed or in `:car`) always stops.
- `gate` — `run` (default) or `skip`: `/android-forge-init` may pass `skip`, since its step 9 formats, records every
  golden and runs the gate once for the whole new project.

The Bash tool may run zsh: brace variables, quote paths. Every `docs/…` path in this prompt is under
`<claude_plugin_root>/`; a form factor's page is `docs/form-factors/<ff>.md`, except `auto` / `automotive` →
`docs/form-factors/cars.md`. Canonical docs: that page (read it
first — its **Quality** section is the bar the form factor ships at), `docs/architecture.md` (ADR 0009: one app
module per device type), `docs/quality.md`. For anything the templates don't cover, ground yourself in current
official guidance — `android docs search "<keywords>"` → `android docs fetch kb://…` — and the form factor's Google
skill (installed in step 5).

## Rules

- Form-factor **app modules** (`:wear`, `:tv`, `:automotive`) share `:app`'s applicationId, have their own namespace
  and `resourcePrefix`, and **never** depend on phone UI modules (`:core:designsystem`, `:core:ui`, phone features) or
  on mobile Material 3 (`androidx.compose.material3`) — Wear uses Wear Compose Material 3, TV `androidx.tv.material3`,
  AAOS the Car App Library's templates. `:wear` and `:tv` depend on `:core:model` / `:core:domain` / `:core:data`;
  `:automotive` links only `:car` until a car screen shows app data. Version codes are offset (`:wear` 100_000_001,
  `:tv` 200_000_001, `:automotive` 300_000_001).
- **Libraries linked into `:app`** (`:car`, `:glasses`, `:widget`) are Android libraries; `:app` gains one
  `implementation(project(":…"))` line and, where noted, manifest or `MainActivity` pieces.
- Plugins come from build-logic by id; catalog entries come from the form factor's `libs.versions.toml.additions`
  (merged with `patch-libs`, which never lowers a version).
- No product behavior invented: the templates render a minimal real screen (the app name, the stored theme mode);
  the product's UI for that device is a later slice.
- Never create an emulator — the calling command asks the user first (`scripts/avd.sh ensure <ff>` downloads a
  system image).
- **Shell state doesn't survive between Bash calls.** Step 1 writes an env file; every later block starts with the
  preamble below — `<preamble>` in a block stands for these two lines (they re-read the file, guard what the block
  needs and `cd` into the project: never rely on a previous block's variables or working directory):
  ```bash
  source "${TMPDIR:-/tmp}/android-forge-form-factor.env"; cd "${TARGET:?}" || exit 1
  : "${BASE_PACKAGE:?}" "${BASE_PACKAGE_PATH:?}" "${APP_NAME:?}" "${PLUGIN:?}"; AO="${PLUGIN}/scripts/apply-overlay.sh"; FFD="${PLUGIN}/overlay/form-factors"
  ```

## Steps

1. **Env file** — one Bash block, with the literal input values:
   ```bash
   export TARGET="<project_root>" PLUGIN="<claude_plugin_root>" FORM_FACTOR="<form_factor>"
   export BASE_PACKAGE="<base_package>" APP_NAME="<app_name>"
   export BASE_PACKAGE_PATH="$(echo "${BASE_PACKAGE}" | tr . /)"
   # auto / automotive only (else ""): the manifest needs the UPPERCASE category suffix — envsubst can't change case.
   export CAR_APP_CATEGORY="$(echo "<car_app_category>" | tr '[:lower:]' '[:upper:]')"
   typeset -p TARGET PLUGIN FORM_FACTOR BASE_PACKAGE BASE_PACKAGE_PATH APP_NAME CAR_APP_CATEGORY \
       > "${TMPDIR:-/tmp}/android-forge-form-factor.env"
   ```
2. **What is already there** — decided from the project itself, never from `CLAUDE.md` (which only gives the app name):
   ```bash
   source "${TMPDIR:-/tmp}/android-forge-form-factor.env"; cd "${TARGET:?}" || exit 1
   for m in wear tv car automotive widget glasses; do
       grep -qF "include(\":${m}\")" settings.gradle.kts && echo "module :${m} — present"
   done
   grep -qF 'project(":car")' app/build.gradle.kts && echo "auto — :app links :car"
   grep -qF 'com.google.android.gms.car.application' app/src/main/AndroidManifest.xml && echo "auto — Android Auto meta-data in :app"
   grep -qF 'android.software.xr.api.spatial' app/src/main/AndroidManifest.xml && echo "xr — present"
   grep -qF 'android.hardware.touchscreen' app/src/main/AndroidManifest.xml && echo "desktop — present"
   grep -qF 'androidx.media3:media3-cast' gradle/libs.versions.toml && echo "cast — present"
   [ -f car/src/main/AndroidManifest.xml ] && grep -oE 'androidx\.car\.app\.category\.[A-Z_]+' car/src/main/AndroidManifest.xml
   grep -E '^androidMinSdk' gradle/libs.versions.toml
   ```
   First, before anything else: `automotive` with `car_app_category: messaging` or a `MESSAGING` `:car` → stop:
   templated messaging is Android Auto only (the recipe blocks refuse it too). Then stop and say what exists when the
   form factor is already there: its module (`wear`, `tv`, `widgets` → `:widget`, `glasses`), `:automotive`
   (`automotive`), `:app` linking `:car` or carrying the Auto meta-data (`auto`), the manifest line (`xr`, `desktop`),
   the `media3-cast` catalog entry (`cast`). `:car` present without the side you're adding (Auto ↔ AAOS): don't
   re-render it — do only the missing side, with the category printed above. `tv` with `androidMinSdk` above 31: carry
   on, and warn in the report that TV ready (TV-PS) wants 31 or lower.
3. **Render + wire** — the form factor's recipe below (each block starts with the preamble).
4. **CLAUDE.md** (Edit tool) — under `## Form factors`, one bullet for the form factor (what it is, its module or
   manifest piece, the quality tier it ships at — its page's Quality section), unless a bullet there already names it;
   under `## Modules`, one `- :<module> — …` line per new module (none for `xr`, `desktop`, `cast`), unless a line
   already names it. Never a second copy of a line.
5. **Skills**: `bash "${PLUGIN}/scripts/skills.sh" install "${TARGET}" <tier>` after the preamble (tier = the form
   factor's; `auto`/`automotive` → `cars`).
6. **Format, record, gate** (`gate: skip` → skip this step and say so in the report). Each Gradle run is its own Bash
   call (timeout 600000); the log keeps the output, the exit code is Gradle's:
   ```bash
   source "${TMPDIR:-/tmp}/android-forge-form-factor.env"; cd "${TARGET:?}" || exit 1; LOG="${TMPDIR:-/tmp}/android-forge-form-factor-gradle.log"
   ./gradlew spotlessApply --console=plain > "${LOG}" 2>&1; rc=$?; tail -20 "${LOG}"; echo "exit=${rc}"
   ```
   `exit=0` → the same block with the recipe's **Record** task — only the module(s) you added
   (`":wear:recordRoborazziDebug"`), never the project-wide `recordRoborazziDebug`, which would silently re-record
   every other module's goldens; skip it when the recipe records nothing — then with the gate,
   `spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true` (`tail -40`). Stop at the first
   non-zero exit and report it with `grep -n "What went wrong" -A15 "${LOG}"`. Look at the new goldens
   (`<module>/src/test/screenshots/`).
7. **Report**: form factor, modules/manifest changes, catalog keys, skill tier, CLAUDE.md lines added (or "already
   there"), gate result (`exit=` and the tail if red, or "skipped"), the emulator command (`bash <plugin>/scripts/avd.sh
   ensure <avd-ff>`, `android emulator start "$(bash <plugin>/scripts/avd.sh name <avd-ff>)"`, the launch command —
   `<avd-ff>` is the form factor itself, except `widgets` → `phone`; no emulator for `auto` (the Desktop Head Unit —
   the steps from `cars.md`) or `cast` (a real Cast device); glasses: a glasses AVD paired with a host phone in Android
   Studio's Pairing Assistant), any warning from step 2, and the form factor's next step from its page.

## Recipes

### `wear` — `:wear` app module (Wear Compose Material 3)

```bash
<preamble>
bash "${AO}" render-module wear "${FFD}/wear/wear" "${TARGET}/wear" "${BASE_PACKAGE_PATH}"
bash "${AO}" patch-settings "${TARGET}" "wear"
bash "${AO}" patch-libs "${TARGET}" "${FFD}/wear/libs.versions.toml.additions"
```

No `:app` edits. minSdk is 30 (Wear OS 3) or the project's, whichever is higher. Tier `wear`. **Record**
`:wear:recordRoborazziDebug` (large/small round and square goldens). Launch:
`android run --apks=wear/build/outputs/apk/debug/wear-debug.apk --device=<s>` (tiles/widgets later:
`--type TILE|WEAR_WIDGET`).

### `tv` — `:tv` app module (Compose for TV)

```bash
<preamble>
bash "${AO}" render-module tv "${FFD}/tv/tv" "${TARGET}/tv" "${BASE_PACKAGE_PATH}"
bash "${AO}" patch-settings "${TARGET}" "tv"
bash "${AO}" patch-libs "${TARGET}" "${FFD}/tv/libs.versions.toml.additions"
```

No `:app` edits. Tier `tv`. **Record** `:tv:recordRoborazziDebug` (1080p dark/light). Launch:
`android run --apks=tv/build/outputs/apk/debug/tv-debug.apk --device=<s> --activity=MainActivity`. Tell the user the
banner (`tv/src/main/res/drawable/tv_banner.xml`) is a placeholder that must become a localized PNG with the app name
before publishing (TV-BN).

### `auto` / `automotive` — `:car` (+ `:automotive`)

Templated categories (`poi` `iot` `weather` `navigation`, and `messaging` for `auto` only) — `:car` is rendered
once, for whichever side comes first (skip this block when step 2 found `:car`):

```bash
<preamble>
: "${CAR_APP_CATEGORY:?car_app_category is required for :car}"
[[ "${FORM_FACTOR}" == automotive && "${CAR_APP_CATEGORY}" == MESSAGING ]] \
    && { echo "✗ templated messaging is Android Auto only — not rendering :car for automotive"; exit 1; }
bash "${AO}" render-module car "${FFD}/cars/car" "${TARGET}/car" "${BASE_PACKAGE_PATH}"
bash "${AO}" patch-libs "${TARGET}" "${FFD}/cars/libs.versions.toml.additions"
bash "${AO}" patch-settings "${TARGET}" "car"
grep -oE 'androidx\.car\.app\.category\.[A-Z_]+' car/src/main/AndroidManifest.xml   # must print your category
# Templated messaging also declares the notification capability (it builds on messaging notifications):
if [[ "${CAR_APP_CATEGORY}" == MESSAGING ]]; then
    perl -pi -e 's#^(\s*)<uses name="template" />#$1<uses name="notification" />\n$1<uses name="template" />#' car/src/main/res/xml/automotive_app_desc.xml
fi
```

`automotive` also renders the AAOS app:

```bash
<preamble>
# Templated messaging is Android Auto only: refuse a messaging category, passed or already in :car.
{ [[ "${CAR_APP_CATEGORY}" == MESSAGING ]] || grep -qF 'androidx.car.app.category.MESSAGING' car/src/main/AndroidManifest.xml 2>/dev/null; } \
    && { echo "✗ templated messaging is Android Auto only — no :automotive"; exit 1; }
bash "${AO}" render-module automotive "${FFD}/cars/automotive" "${TARGET}/automotive" "${BASE_PACKAGE_PATH}"
bash "${AO}" patch-settings "${TARGET}" "automotive"
```

`auto` edits `:app` (never for `automotive`):
1. `app/build.gradle.kts`: `implementation(project(":car"))` after the `:core:navigation` line.
2. `app/src/main/AndroidManifest.xml`: paste `${FFD}/cars/app-manifest-snippet.xml` (the
   `com.google.android.gms.car.application` meta-data) inside `<application>`. AAOS must never carry it.

Category extras (`docs/form-factors/cars.md` § Manifest split): `navigation` → the `androidx.car.app.NAVIGATION_TEMPLATES`
permission in `:car`'s manifest and, for `automotive`, `APP_MAPS` + the `NAVIGATE`/`geo:` filter on `CarAppActivity`;
`poi` with map templates → `androidx.car.app.MAP_TEMPLATES`; `messaging` → tell the user the app must also post
`MessagingStyle` notifications for Android Auto (`android docs fetch kb://android/training/cars/communication/notification-messaging`)
and that templated messaging publishes to internal/closed testing tracks only.

`media` and `parked` render nothing: follow their recipes in `docs/form-factors/cars.md` (ground the media service in
`android docs search "media3 MediaLibraryService android auto"`; parked in the `android-for-cars-parked-apps` skill) and
report what you added. Tier `cars`. **Record** nothing (`:car` screens are host-rendered templates; their tests are
plain unit tests). Launch (AAOS): `android run --apks=automotive/build/outputs/apk/debug/automotive-debug.apk --device=<s>`;
Android Auto is the Desktop Head Unit (manual — tell the user the steps from the doc).

### `widgets` — `:widget` (Glance) into `:app`

```bash
<preamble>
bash "${AO}" render-module widget "${FFD}/widgets/widget" "${TARGET}/widget" "${BASE_PACKAGE_PATH}"
bash "${AO}" patch-settings "${TARGET}" "widget"
bash "${AO}" patch-libs "${TARGET}" "${FFD}/widgets/libs.versions.toml.additions"
```

One `:app` edit: `implementation(project(":widget"))` after the `:core:navigation` line in `app/build.gradle.kts`; the
receiver's manifest merges. Tier `widgets`. **Record** nothing (Glance unit tests). Tell the user the CLI can't
long-press, so placing the widget on the home screen is manual, and that Glance's WorkManager adds four permissions
to `:app`'s merged manifest.

### `glasses` — `:glasses` (Jetpack Compose Glimmer, projected) into `:app`

```bash
<preamble>
bash "${AO}" render-module glasses "${FFD}/glasses/glasses" "${TARGET}/glasses" "${BASE_PACKAGE_PATH}"
bash "${AO}" patch-settings "${TARGET}" "glasses"
bash "${AO}" patch-libs "${TARGET}" "${FFD}/glasses/libs.versions.toml.additions"
```

`:app` edits — the entry point goes on a surface `:app` owns for good (never `Home.kt`, which a feature taking over
the start destination deletes; never inside a feature):
1. `app/build.gradle.kts`: `implementation(project(":glasses"))` after the `:core:navigation` line.
2. `app/src/main/kotlin/<base path>/MainActivity.kt`: inside `AppTheme { }`, wrap the `AppNavigation(…)` call in a
   `Box(Modifier.fillMaxSize())` and add, after it:
   ```kotlin
   // :glasses — shown over every screen while display glasses are connected; starts the experience on them.
   LaunchOnGlassesButton(
       modifier = Modifier.align(Alignment.BottomEnd).safeDrawingPadding().padding(AppSpacing.md),
       hideWhileDisconnected = true,
   )
   ```
   (imports: `androidx.compose.foundation.layout.{Box, fillMaxSize, padding, safeDrawingPadding}`,
   `androidx.compose.ui.{Alignment, Modifier}`, `<base>.core.designsystem.AppSpacing`, `<base>.glasses.LaunchOnGlassesButton`).
   Hidden while disconnected — so no screen's golden changes. If the user names another `:app`-owned surface (an
   app-level top bar), place it there with the default `hideWhileDisconnected = false` (disabled until glasses connect).

Tier `glasses`. **Record** nothing. The versions are the docs' exact pins — don't raise them.

### `xr` — XR headset readiness (same APK)

No module, no dependency. Paste `${FFD}/xr/app-manifest-snippet.xml` (`android.software.xr.api.spatial`,
`required="false"`) into `app/src/main/AndroidManifest.xml` as a direct child of `<manifest>`. Tier `xr`. **Record**
nothing. After the gate, check every merged `<uses-feature>` is not required:
`aapt2 dump badging app/build/outputs/apk/debug/app-debug.apk | grep uses-feature` (aapt2 lives under
`$(android info sdk)/build-tools/<newest>/`) — only `uses-feature-not-required` lines, except a required
`android.hardware.faketouch` while `desktop`'s touchscreen line is absent (implied, and fine for XR). The differentiated tier (spatial panels) is product work —
`docs/form-factors/xr.md`.

### `desktop` — Googlebook / ChromeOS readiness (same APK)

No module, no dependency. Paste `${FFD}/desktop/app-manifest-snippet.xml` (`android.hardware.touchscreen`,
`required="false"`) into `app/src/main/AndroidManifest.xml` as a direct child of `<manifest>`, then, after the gate,
run the same `aapt2 dump badging … | grep uses-feature` check as `xr` (every line `uses-feature-not-required`; no
`faketouch` line remains once the touchscreen isn't required). The caption-bar tint is already in the scaffold's `MainActivity`. Tier `desktop`. **Record**
nothing. Keyboard/pointer polish is per feature — `docs/form-factors/desktop.md`.

### `cast` — Google Cast sender

No module yet: `bash "${AO}" patch-libs "${TARGET}" "${FFD}/cast/libs.versions.toml.additions"` after the preamble
(Media3 incl. `media3-cast`), tier `cast`, and a `## Form factors` bullet saying the first media slice creates
`:core:media` per `docs/form-factors/cast.md` and the `media3-cast-integration` skill. **Record** nothing; no gate change
expected (unused catalog entries).

## What you do NOT do

- Commit, push, or create emulators.
- Build the product's device UI beyond the template — that's a slice with its own spec.
- Re-record goldens of modules you didn't add.
- Report success on a red gate.
