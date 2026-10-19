# Android for Cars — Android Auto and Android Automotive OS

Two platforms, opted into separately, sharing one library:

- **Android Auto** — the phone app projects onto the car's screen. No separate APK: `:app` links **`:car`**.
- **Android Automotive OS (AAOS)** — Android runs in the car. A separate **`:automotive` app module** (same
  applicationId, minSdk 29, its own Play track) links the same **`:car`**.

`:car` is an Android library holding the Car App Library service, session and screens. What it contains depends on
the **app category**, asked at add time:

| Category | What android-forge renders | Notes |
|---|---|---|
| `poi`, `iot`, `weather`, `navigation`, `messaging` (templated) | `:car` (Car App Library) + `:app` / `:automotive` wiring | the template's screen is a generic `ListTemplate`, valid for every templated category |
| `media` | nothing — recipe below | Media3 `MediaLibraryService`, the host draws the UI |
| `parked` (video, games, browsers) | nothing — recipe below | full-screen activity while parked; `android-for-cars-parked-apps` skill |

## Add it (templated categories)

```bash
export CAR_APP_CATEGORY="$(echo "<poi|iot|weather|navigation|messaging>" | tr '[:lower:]' '[:upper:]')"   # envsubst needs the UPPERCASE suffix
FFD="${CLAUDE_PLUGIN_ROOT}/overlay/form-factors/cars"
AO="${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh"
bash "${AO}" render-module car "${FFD}/car" "${TARGET}/car" "${BASE_PACKAGE_PATH}"
bash "${AO}" render-module automotive "${FFD}/automotive" "${TARGET}/automotive" "${BASE_PACKAGE_PATH}"   # AAOS only
bash "${AO}" patch-settings "${TARGET}" "car,automotive"                                                    # drop automotive for Auto only
bash "${AO}" patch-libs "${TARGET}" "${FFD}/libs.versions.toml.additions"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" install "${TARGET}" cars
```

**Android Auto** also edits `:app` (skip both for AAOS only):
1. `app/build.gradle.kts`: `implementation(project(":car"))`.
2. `app/src/main/AndroidManifest.xml`, inside `<application>`: the contents of
   `overlay/form-factors/cars/app-manifest-snippet.xml` — `<meta-data android:name="com.google.android.gms.car.application" android:resource="@xml/automotive_app_desc" />`.

## Manifest split

| Module | Carries |
|---|---|
| `:car` | the exported `MainCarAppService` (`androidx.car.app.CarAppService` action + `androidx.car.app.category.<CATEGORY>`; `tools:ignore="ExportedService"` — the host can't hold a permission, `createHostValidator()` decides), `androidx.car.app.minCarApiLevel` (7: `ListTemplate` headers), `res/xml/automotive_app_desc.xml` (`<uses name="template"/>`) |
| `:app` | only the Android Auto meta-data above — AAOS must never carry it |
| `:automotive` | `android.hardware.type.automotive` (required), `android.software.car.templates_host` (required), wifi/portrait/landscape `required="false"`, `com.android.automotive` meta-data, `androidx.car.app.activity.CarAppActivity` (`singleTask`, `Theme.DeviceDefault.NoActionBar`, `distractionOptimized`) |

Host validation: debug builds allow every host (the Desktop Head Unit, emulators); release builds only Google's hosts
(`car_hosts_allowlist`, a copy of the library's private sample — re-sync it when `androidxCarApp` is bumped).

Category extras: **navigation** declares `androidx.car.app.NAVIGATION_TEMPLATES` and, on `CarAppActivity`, `APP_MAPS`
plus a `androidx.car.app.action.NAVIGATE` / `geo:` intent filter; **POI** map templates need `androidx.car.app.MAP_TEMPLATES`;
a weather app that also navigates declares both categories.

## Building car screens

- Car App Library `Screen`s return templates (`ListTemplate`, `PaneTemplate`, `GridTemplate`, `MessageTemplate`,
  map/navigation templates by category); the host renders them — no Compose. Each template API has a minimum Car API
  level (`@RequiresCarApi`); raise `minCarApiLevel` to the newest one a screen uses. `ListTemplate.setTitle` is
  deprecated: use `setHeader` (level 7).
- Domain data: make `MainCarAppService` an `@AndroidEntryPoint` (apply `android-forge.hilt` to `:car`), inject use cases
  there and pass them into the session — `Session`/`Screen` aren't Hilt entry points (validated: compiles and renders
  on AAOS).
- Driver distraction: templated apps are distraction-optimized by construction; keep text short and actions few
  (car app quality's DD- checks). `distractionOptimized` isn't honored for apps sideloaded onto Play images.

## Media apps (recipe — no `:car`)

A Media3 `MediaLibraryService` + `MediaLibrarySession` (`media3-session` + exoplayer) — exported,
`foregroundServiceType="mediaPlayback"`, intent filter actions `androidx.media3.session.MediaLibraryService` and
`android.media.browse.MediaBrowserService`, `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permissions;
support at least play/pause, stop, set-media-item and prepare. Android Auto: the `:app` meta-data pointing at an
`automotive_app_desc` with `<uses name="media"/>`. AAOS: an `:automotive` app (minSdk 28, `appCategory="audio"`,
`type.automotive` required, wifi/portrait/landscape not required, `com.android.automotive` → `media`) with **no**
`MAIN`/`LAUNCHER` activity — only settings/sign-in activities reached by explicit intent. Share the service code from a
`:core:media` library (see [cast.md](cast.md) for the same module).

## Parked apps (recipe — `android-for-cars-parked-apps` skill)

Video, games and browsers run full screen while the car is parked. Android Auto: add `CAR_LAUNCHER` to `:app`'s `MAIN`
intent filter (Auto supports only games). AAOS, same APK on the mobile track: `type.automotive required="false"`,
`appCategory="video|game"` (browsers: the `APP_BROWSER` category), wifi/portrait/landscape/camera not required; the
activity handles `configChanges` for display continuity, is **never** `distractionOptimized`, and offers in-app
back/close; cutout mode in `values-car-v30`; pause on `ON_PAUSE` and react to `CarUxRestrictionsManager`
(`useLibrary("android.car")`). Car-ready mobile apps (an invite-only program) reach AAOS cars in compatibility mode.

## Skills

`android-for-cars-parked-apps` (parked apps only). No official skill covers templated Car App Library apps — this page
and `android docs search "car app library <template>"` are the reference.

## QA

- **AAOS**: `bash scripts/avd.sh ensure automotive` → `automotive_1408p_landscape_with_play` (API 35 ext15, Play image);
  `android run` the `:automotive` APK; `CarAppActivity` renders the template (validated: header with the app name, the
  welcome row). `android layout` reads it.
- **Android Auto**: the Desktop Head Unit (`android sdk install extras/google/auto`; enable the head unit server in
  Android Auto's developer settings on the phone, `adb forward tcp:5277 tcp:5277`, run `desktop-head-unit`). The
  `android-qa` agent can't drive it — Auto scenarios are verified by hand.
- Tests: `androidx.car.app:app-testing` — `TestCarContext` + `ScreenController`; call `screen.invalidate()` before
  reading `templatesReturned`.

## Quality

Car ready for the chosen category (car app quality: distraction, navigation, media checks per category) — see
[quality.md](../quality.md).
