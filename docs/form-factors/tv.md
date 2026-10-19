# TV / Google TV

A **`:tv` app module** — its own APK with `:app`'s applicationId on the TV Play track (ADR 0009; Google also allows one
APK for phone + TV, but TV UI is different enough that android-forge keeps it separate). It reuses `:core:model` /
`:core:domain` / `:core:data`, never the phone UI modules: TV uses **Compose for TV** (`androidx.tv:tv-material`).

## Add it

`/android-forge-add-form-factor tv`:

```bash
FF=tv
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render-module "${FF}" "${CLAUDE_PLUGIN_ROOT}/overlay/form-factors/${FF}/${FF}" "${TARGET}/${FF}" "${BASE_PACKAGE_PATH}"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-settings "${TARGET}" "${FF}"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-libs "${TARGET}" "${CLAUDE_PLUGIN_ROOT}/overlay/form-factors/${FF}/libs.versions.toml.additions"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" install "${TARGET}" tv
```

No edits to `:app`. The template ships `MainApplication`, `MainActivity`, `TvTheme` (tv-material `MaterialTheme`
following the stored theme mode, plus `TvSpacing` with the 48dp × 27dp overscan margins), a home screen with a row of
focusable `ClassicCard`s (focus scale, the first card focused initially) driven by an Orbit `TvHomeViewModel`, strings
with the `tv_` prefix, and tests: Orbit ViewModel tests and Robolectric screen tests on `Television1080p` — D-pad keys
(`DirectionRight` moves focus, `DirectionCenter` selects) plus dark/light goldens.

## Manifest essentials

- `<uses-feature android:name="android.software.leanback" android:required="true" />` (a TV-only module).
- `<uses-feature android:name="android.hardware.touchscreen" android:required="false" />` — otherwise Play hides the
  app on TVs. Same for any other hardware a TV lacks (camera, telephony, GPS, microphone).
- Launcher: `MAIN` + `LEANBACK_LAUNCHER` only; `android:banner` (320×180 px at xhdpi = 160×90dp) and `android:icon`
  (no `roundIcon`).
- **The banner placeholder must be replaced before publishing**: TV quality rule TV-BN wants the app name in the banner,
  localized — export a PNG per language.
- `versionCode` starts at `200_000_001`.

## Building TV UI

- tv-material components (`Card`/`ClassicCard`, `Button`, `Surface`, `Carousel`), standard lazy layouts (the `TvLazy*`
  ones are gone); every interactive element focusable with a visible focus state; a sensible initial focus
  (`FocusRequester`) and focus restoration when returning to a row (`focusRestorer`).
- Overscan-safe layout: 48dp horizontal / 27dp vertical margins for content; backgrounds may bleed.
- Playback: Media3 with `media3-ui-compose`'s `PlayerSurface`; Google TV discovery via the Engage SDK
  (`engage-sdk-integration` skill); receiving casts is Cast Connect.
- D-pad first: no gestures, no hover; text input via the on-screen keyboard.

## Skills

`leanback-to-compose-tv-migration` (the most complete Compose-for-TV reference — focus, carousels, overscan, playback),
`engage-sdk-integration` (Google TV Continue Watching / recommendations).

## QA

`bash scripts/avd.sh ensure tv` → `tv_1080p` (Android TV, API 36). TV images ship Play Protect, which blocks the CLI's
instrumentation server; `ensure` boots the new AVD once and turns app verification off inside it, so `android layout`
and `android input` work. Launch with
`android run --apks=<apk> --device=<s> --activity=MainActivity` (leanback-only launchers fail the CLI's component check
otherwise); drive with D-pad keys — `android input --device=<s> key 19|20|21|22` (up/down/left/right) and `key 23`
(center); before pressing center, check the target's `state` contains `FOCUSED` in `android layout`.

## Quality

TV ready: leanback launcher + banner, D-pad navigation everywhere with visible focus, overscan-safe layout, no
touchscreen requirement, back exits from the top level — see [quality.md](../quality.md).
