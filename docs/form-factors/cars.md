# Android for Cars — Android Auto and Android Automotive OS

Two platforms, opted into separately, sharing one library:

- **Android Auto** — the phone app projects onto the car's screen. No separate APK: `:app` links **`:car`**.
- **Android Automotive OS (AAOS)** — Android runs in the car. A separate **`:automotive` app module** (same
  applicationId, minSdk 29 or the project's when higher, its own Play track) links the same **`:car`**.

`:car` is an Android library holding the Car App Library service, session and screens. What it contains depends on
the **app category**, asked at add time:

| Category | Platforms | What android-forge renders | Notes |
|---|---|---|---|
| `poi`, `iot`, `weather`, `navigation` (templated) | Auto + AAOS | `:car` (Car App Library) + `:app` / `:automotive` wiring | the template's screen is a generic `ListTemplate`, valid for every templated category |
| `messaging` (templated, labs) | **Android Auto only** | `:car` + `:app` wiring | Play accepts it on internal and closed testing tracks only; builds on `MessagingStyle` notifications (below) |
| `media` | Auto + AAOS | nothing — recipe below | Media3 `MediaLibraryService`, the host draws the UI |
| `parked` (video, games, browsers) | games: both; video, browsers: AAOS | nothing — recipe below | full-screen activity while parked; `android-for-cars-parked-apps` skill |

## Add it (templated categories)

`/android-forge-add-form-factor auto|automotive` — the `android-form-factor-builder` agent runs these in one shell
(its recipe re-reads an env file in every block; `BASE_PACKAGE`, `APP_NAME` exported):

```bash
: "${TARGET:?}" "${BASE_PACKAGE_PATH:?}"
export CAR_APP_CATEGORY="$(echo "<poi|iot|weather|navigation|messaging>" | tr '[:lower:]' '[:upper:]')"   # envsubst needs the UPPERCASE suffix
FFD="${CLAUDE_PLUGIN_ROOT}/overlay/form-factors/cars"
AO="${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh"
bash "${AO}" render-module car "${FFD}/car" "${TARGET}/car" "${BASE_PACKAGE_PATH}"
bash "${AO}" render-module automotive "${FFD}/automotive" "${TARGET}/automotive" "${BASE_PACKAGE_PATH}"   # AAOS only
bash "${AO}" patch-settings "${TARGET}" "car,automotive"                                                    # drop automotive for Auto only
bash "${AO}" patch-libs "${TARGET}" "${FFD}/libs.versions.toml.additions"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" install "${TARGET}" cars
```

`messaging` (Auto only — never with `automotive`) also adds `<uses name="notification" />` next to
`<uses name="template" />` in `car/src/main/res/xml/automotive_app_desc.xml`.

**Android Auto** also edits `:app` (skip both for AAOS only):
1. `app/build.gradle.kts`: `implementation(project(":car"))`.
2. `app/src/main/AndroidManifest.xml`, inside `<application>`: the contents of
   `overlay/form-factors/cars/app-manifest-snippet.xml` — `<meta-data android:name="com.google.android.gms.car.application" android:resource="@xml/automotive_app_desc" />`.

## Manifest split

| Module | Carries |
|---|---|
| `:car` | the exported `MainCarAppService` (`androidx.car.app.CarAppService` action + `androidx.car.app.category.<CATEGORY>`; `tools:ignore="ExportedService"` — the host can't hold a permission, `createHostValidator()` decides), `androidx.car.app.minCarApiLevel` (7: `ListTemplate` headers, `ConversationItem`), `res/xml/automotive_app_desc.xml` (`<uses name="template"/>`, plus `<uses name="notification"/>` for messaging) |
| `:app` | only the Android Auto meta-data above — AAOS must never carry it |
| `:automotive` | `android.hardware.type.automotive` (required), `android.software.car.templates_host` (required), wifi/portrait/landscape/camera `required="false"` (Play's AAOS list — also when a permission implies them), `com.android.automotive` meta-data, `androidx.car.app.activity.CarAppActivity` (`singleTask`, `Theme.DeviceDefault.NoActionBar`, `distractionOptimized`) |

Host validation: debug builds allow every host (the Desktop Head Unit, emulators); release builds only Google's hosts
(`car_hosts_allowlist`, a copy of the library's private sample — re-sync it when `androidxCarApp` is bumped).

Category extras: **navigation** declares `androidx.car.app.NAVIGATION_TEMPLATES` and, on `CarAppActivity`, `APP_MAPS`
plus a `androidx.car.app.action.NAVIGATE` / `geo:` intent filter; **POI** map templates need `androidx.car.app.MAP_TEMPLATES`;
a weather app that also navigates declares both categories. **Messaging** (Auto only) must also extend its messaging
notifications to Android Auto — `MessagingStyle` notifications with reply and mark-as-read actions handled by a
`Service` (`android docs fetch kb://android/training/cars/communication/notification-messaging`) — and lists
conversations as `ConversationItem`s in a `ListTemplate` (Car API 7; `kb://android/training/cars/communication/templated-messaging`).

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
`automotive_app_desc` with `<uses name="media"/>`. AAOS: an `:automotive` app (minSdk 29, android-forge's floor —
AAOS media itself needs 28; `appCategory="audio"`,
`type.automotive` required, wifi/portrait/landscape/camera not required, `com.android.automotive` → `media`) with **no**
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

Play reviews templated (driving) apps at **Car optimized** and parked apps at **Car ready**
(`android docs fetch kb://android/docs/quality-guidelines/car-app-quality/index` — filter by category). The template
host enforces the driver-distraction basics; the rest is the product's. The list below is what applies to the
categories android-forge renders or documents.

**Every templated category** (POI, IoT, weather, navigation, messaging):
- `PC-1` only the declared category's features · `EP-1` works as the Play listing says · `EP-2` a relaunch from the
  home screen restores the previous state · `EP-4` (AAOS) the listing has Android Automotive OS screenshots.
- `PE-1` (AAOS) no functionality in the app's own activities except setup, settings and sign-in while parked — the
  templates host draws the rest.
- `SA-1` no animations · `ST-1` no auto-scrolling text · `IU-1` no images beyond the allowed exceptions · `AD-1` /
  `NA-1` no ads beyond an advertiser or product name, none in notifications · `IN-1` notifications only when relevant
  to the driver.
- `AC-1` every task completes in five screens or fewer (the template step limit) · `DR-1` buttons respond within 2 s ·
  `DR-2` launch within 10 s · `DR-3` content loads within 10 s.
- `VI-1` (Android Auto) a step that needs the phone tells the user to look at it only when it's safe ·
  `VD-1` icons and colors meet Android Auto's contrast · `TH-1` custom theming (Car App Library ≥ 1.9) supports light
  and dark · `PA-1` (navigation, POI, IoT, weather) purchases are one-step on an existing method — no payment setup,
  no multi-item carts, no subscriptions.

**Per category:**
- POI — `PF-1` meaningful driving-related functionality; `MR-1` light/dark maps when it draws maps.
- IoT — `IT-1` while driving: view device state, one-touch on/off, event notifications; never setup, editing or
  fine-grained control.
- Weather — `WE-1` content for the current or a chosen location · `WE-2` readable map tiles, at most three legends ·
  `WE-3` readable forecast icons · `WE-4` no forecast-interval customization in templates · `WE-5` at most five map
  annotation types per view · `MR-1`.
- Navigation — `NF-1`…`NF-7` (turn-by-turn directions, map-only drawing surface, turn-by-turn notifications, cluster
  metadata, stay quiet while another app navigates, handle navigation intents, a test-drive mode) · `DD-1` the
  navigation audio channel only for instructions · `VC-1` voice commands · `MR-1`.
- Messaging (Android Auto) — `MF-1`…`MF-5` (receive messages, grouped and ordered, reply, short-form only,
  peer-to-peer only) through `MessagingStyle` notifications; `TMF-1` (differentiated) conversations in templates.

**Parked apps** (Car ready): `DD-3` not launchable or usable while driving and silent (or `DD-2` for audio) ·
`IN-2` no heads-up notifications · `AN-1` no dead ends · `AR-1` nothing interactive under system bars or cutouts ·
`DO-1` (AAOS) works on fixed-orientation screens · `LS-C1`/`LS-C2` configuration continuity; browsers also
`SD-1`/`SD-2`.

The reviewer checks the manifest side (Auto meta-data only in `:app`, `minCarApiLevel` at or above every
`@RequiresCarApi` used, messaging's notification capability); QA runs AAOS journeys, Android Auto is checked by hand
on the Desktop Head Unit.
