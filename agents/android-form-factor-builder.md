---
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
---

# android-form-factor-builder

You add **one** form factor to an android-forge project. Inputs:

- `form_factor` — `wear` · `tv` · `auto` · `automotive` · `glasses` · `widgets` · `xr` · `desktop` · `cast`
- `project_root` (absolute), `base_package`, `claude_plugin_root` (absolute)
- `car_app_category` — `auto`/`automotive` only: `poi` · `iot` · `weather` · `navigation` · `messaging` (templated —
  renders `:car`), `media` or `parked` (recipes, no `:car`)

The Bash tool may run zsh: brace variables, quote paths. Canonical docs: `<claude_plugin_root>/docs/form-factors/<ff>.md`
(read the one you're adding first), `docs/architecture.md` (ADR 0009: one app module per device type),
`docs/quality.md`. For anything the templates don't cover, ground yourself in current official guidance —
`android docs search "<keywords>"` → `android docs fetch kb://…` — and the form factor's Google skill (installed in
step 4).

## Rules

- Form-factor **app modules** (`:wear`, `:tv`, `:automotive`) share `:app`'s applicationId, have their own namespace and
  `resourcePrefix`, depend on `:core:model` / `:core:domain` / `:core:data` and **never** on phone UI modules or phone
  features. Their version codes are offset (`:wear` 100_000_001, `:tv` 200_000_001, `:automotive` 300_000_001).
- **Libraries linked into `:app`** (`:car`, `:glasses`, `:widget`) are Android libraries; `:app` gains one
  `implementation(project(":…"))` line and, where noted, manifest pieces.
- Plugins come from build-logic by id; catalog entries come from the form factor's `libs.versions.toml.additions`
  (merged with `patch-libs`, which never lowers a version).
- No product behavior invented: the templates render a minimal real screen (the app name, the stored theme mode);
  the product's UI for that device is a later slice.
- Never create an emulator — the calling command asks the user first (`scripts/avd.sh ensure <ff>` downloads a
  system image).

## Steps

1. **Read** the project `CLAUDE.md` (base package, form factors present) and `settings.gradle.kts`. The form factor is
   already present → stop and say what exists. `auto` when `automotive` exists (or vice versa): `:car` is already there —
   only do the side that's missing.
2. **Export** (one Bash block; reuse in later blocks):
   ```bash
   export BASE_PACKAGE="${base_package}" BASE_PACKAGE_PATH="$(echo "${base_package}" | tr . /)"
   export APP_NAME="<from CLAUDE.md>" TARGET="${project_root}"
   # cars only — the manifest needs the UPPERCASE category suffix (envsubst can't change case):
   export CAR_APP_CATEGORY="$(echo "${car_app_category}" | tr '[:lower:]' '[:upper:]')"
   AO="${claude_plugin_root}/scripts/apply-overlay.sh"; FFD="${claude_plugin_root}/overlay/form-factors"
   ```
3. **Render + wire** — the form factor's recipe below.
4. **Skills**: `bash "${claude_plugin_root}/scripts/skills.sh" install "${TARGET}" <tier>` (tier = the form factor's;
   `auto`/`automotive` → `cars`).
5. **CLAUDE.md**: add the form factor's bullet under `## Form factors` (what it is, its module, quality tier) and new
   modules to `## Modules`.
6. **Format, record, gate** (allow several minutes):
   ```bash
   cd "${TARGET}" || exit 1
   ./gradlew spotlessApply -q 2>&1 | tail -10
   ./gradlew recordRoborazziDebug -q 2>&1 | tail -10        # goldens for the new module(s)
   ./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true --console=plain 2>&1 | tail -30
   ```
   Look at the new goldens (`<module>/src/test/screenshots/`).
7. **Report**: form factor, modules/manifest changes, catalog keys, skill tier, CLAUDE.md edit, gate result (verbatim
   tail if red), the emulator command (`bash <plugin>/scripts/avd.sh ensure <ff>`, `android emulator start
   "$(bash <plugin>/scripts/avd.sh name <ff>)"`, the launch command), and the form factor's next step from its doc.

## Recipes

### `wear` — `:wear` app module (Wear Compose Material 3)

```bash
bash "${AO}" render-module wear "${FFD}/wear/wear" "${TARGET}/wear" "${BASE_PACKAGE_PATH}"
bash "${AO}" patch-settings "${TARGET}" "wear"
bash "${AO}" patch-libs "${TARGET}" "${FFD}/wear/libs.versions.toml.additions"
```

No `:app` edits. Tier `wear`. Launch: `android run --apks=wear/build/outputs/apk/debug/wear-debug.apk --device=<s>`
(tiles/widgets later: `--type TILE|WEAR_WIDGET`).

### `tv` — `:tv` app module (Compose for TV)

```bash
bash "${AO}" render-module tv "${FFD}/tv/tv" "${TARGET}/tv" "${BASE_PACKAGE_PATH}"
bash "${AO}" patch-settings "${TARGET}" "tv"
bash "${AO}" patch-libs "${TARGET}" "${FFD}/tv/libs.versions.toml.additions"
```

No `:app` edits. Tier `tv`. Launch: `android run --apks=tv/build/outputs/apk/debug/tv-debug.apk --device=<s> --activity=MainActivity`.
Tell the user the banner (`tv/src/main/res/drawable/tv_banner.xml`) is a placeholder that must become a localized PNG
with the app name before publishing.

### `auto` / `automotive` — `:car` (+ `:automotive`)

Templated categories (`poi` `iot` `weather` `navigation` `messaging`) — `:car` is rendered once, for whichever side
comes first:

```bash
bash "${AO}" render-module car "${FFD}/cars/car" "${TARGET}/car" "${BASE_PACKAGE_PATH}"
bash "${AO}" patch-libs "${TARGET}" "${FFD}/cars/libs.versions.toml.additions"
bash "${AO}" patch-settings "${TARGET}" "car"
# automotive only:
bash "${AO}" render-module automotive "${FFD}/cars/automotive" "${TARGET}/automotive" "${BASE_PACKAGE_PATH}"
bash "${AO}" patch-settings "${TARGET}" "automotive"
```

`auto` also edits `:app` (never for `automotive`):
1. `app/build.gradle.kts`: `implementation(project(":car"))` after the `:core:navigation` line.
2. `app/src/main/AndroidManifest.xml`: paste `${FFD}/cars/app-manifest-snippet.xml` (the
   `com.google.android.gms.car.application` meta-data) inside `<application>`. AAOS must never carry it.

Category extras (`docs/form-factors/cars.md` § Manifest split): `navigation` → the `androidx.car.app.NAVIGATION_TEMPLATES`
permission in `:car`'s manifest and, for `automotive`, `APP_MAPS` + the `NAVIGATE`/`geo:` filter on `CarAppActivity`;
`poi` with map templates → `androidx.car.app.MAP_TEMPLATES`.

`media` and `parked` render nothing: follow their recipes in `docs/form-factors/cars.md` (ground the media service in
`android docs search "media3 MediaLibraryService android auto"`; parked in the `android-for-cars-parked-apps` skill) and
report what you added. Tier `cars`. Launch (AAOS):
`android run --apks=automotive/build/outputs/apk/debug/automotive-debug.apk --device=<s>`; Auto is the Desktop Head Unit
(manual — tell the user the steps from the doc).

### `widgets` — `:widget` (Glance) into `:app`

```bash
bash "${AO}" render-module widget "${FFD}/widgets/widget" "${TARGET}/widget" "${BASE_PACKAGE_PATH}"
bash "${AO}" patch-settings "${TARGET}" "widget"
bash "${AO}" patch-libs "${TARGET}" "${FFD}/widgets/libs.versions.toml.additions"
```

One `:app` edit: `implementation(project(":widget"))` in `app/build.gradle.kts`; the receiver's manifest merges. Tier
`widgets`. Tell the user the CLI can't long-press, so placing the widget on the home screen is manual, and that Glance's
WorkManager adds four permissions to `:app`'s merged manifest.

### `glasses` — `:glasses` (Jetpack Compose Glimmer, projected) into `:app`

```bash
bash "${AO}" render-module glasses "${FFD}/glasses/glasses" "${TARGET}/glasses" "${BASE_PACKAGE_PATH}"
bash "${AO}" patch-settings "${TARGET}" "glasses"
bash "${AO}" patch-libs "${TARGET}" "${FFD}/glasses/libs.versions.toml.additions"
```

`:app` edits: `implementation(project(":glasses"))`, and `LaunchOnGlassesButton()` on a surface `:app` owns — the start
screen (`Home.kt`: wrap its content in a `Column`) unless the user names another; never inside a feature. The button
renders (disabled) on API 36+, which includes Robolectric's pinned SDK 36 — re-record any golden of the screen you put it
on. Tier `glasses`. The versions are the docs' exact pins — don't raise them.

### `xr` — XR headset readiness (same APK)

No module, no dependency. Paste `${FFD}/xr/app-manifest-snippet.xml` (`android.software.xr.api.spatial`,
`required="false"`) into `app/src/main/AndroidManifest.xml` as a direct child of `<manifest>`. Tier `xr`. Check every
merged `<uses-feature>` is not required:
`aapt2 dump badging app/build/outputs/apk/debug/app-debug.apk | grep uses-feature` (aapt2 lives under
`$(android info sdk)/build-tools/<newest>/`). The differentiated tier (spatial panels) is product work —
`docs/form-factors/xr.md`.

### `desktop` — Googlebook / ChromeOS readiness (same APK)

No module, no dependency. Paste `${FFD}/desktop/app-manifest-snippet.xml` (`android.hardware.touchscreen`,
`required="false"`) into `app/src/main/AndroidManifest.xml` as a direct child of `<manifest>`, then run the same
`aapt2 dump badging … | grep uses-feature` check as `xr` (every line `uses-feature-not-required`, plus the implied
`faketouch`). The caption-bar tint is already in the scaffold's `MainActivity`. Tier `desktop`. Keyboard/pointer polish
is per feature — `docs/form-factors/desktop.md`.

### `cast` — Google Cast sender

No module yet: `patch-libs` with `${FFD}/cast/libs.versions.toml.additions` (Media3 incl. `media3-cast`), tier `cast`,
and a `CLAUDE.md` note that the first media slice creates `:core:media` per `docs/form-factors/cast.md` and the
`media3-cast-integration` skill. No gate change expected (unused catalog entries).

## What you do NOT do

- Commit, push, or create emulators.
- Build the product's device UI beyond the template — that's a slice with its own spec.
- Report success on a red gate.
