# Wear OS

A **`:wear` app module** — its own APK with `:app`'s applicationId, on its own Play track (ADR 0009). It reuses
`:core:model` / `:core:domain` / `:core:data`, never the phone UI modules: Wear has its own components (Wear Compose
Material 3), theme and navigation.

## Add it

`/android-forge-add-form-factor wear` (the `android-form-factor-builder` agent):

```bash
FF=wear
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render-module "${FF}" "${CLAUDE_PLUGIN_ROOT}/overlay/form-factors/${FF}/${FF}" "${TARGET}/${FF}" "${BASE_PACKAGE_PATH}"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-settings "${TARGET}" "${FF}"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-libs "${TARGET}" "${CLAUDE_PLUGIN_ROOT}/overlay/form-factors/${FF}/libs.versions.toml.additions"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" install "${TARGET}" wear
```

No edits to `:app`. The template ships `MainApplication` (`@HiltAndroidApp`), `MainActivity` (`@AndroidEntryPoint`),
`WearApp` (Wear M3 `MaterialTheme` + `AppScaffold`), a home screen (`ScreenScaffold` + `TransformingLazyColumn`) with an
Orbit `WearHomeViewModel` that reads and writes the stored theme mode through `:core:domain` use cases (proving the
shared graph works on the watch), strings with the `wear_` prefix, and tests: Orbit ViewModel tests, a screen test, and
Roborazzi goldens on `WearOSLargeRound` / `WearOSSmallRound` (fixed `TimeSource`, so the clock never changes them).

## Manifest and build essentials

- `<uses-feature android:name="android.hardware.type.watch" />` — never `required="false"` (one APK for phone + watch
  isn't supported).
- `com.google.android.wearable.standalone` = `true`: every core feature works without the phone app. Set `false` only
  when the watch genuinely needs the phone (and add the phone-side install prompt).
- `android:taskAffinity=""` on the launcher activity (Lint `WearRecents`); a second launcher activity (a tile's or a
  notification's target) gets its own affinity.
- `android:icon` + `android:roundIcon` (adaptive, with a monochrome layer).
- `minSdk = 30` (Wear OS 3, the oldest version the quality guidelines test); Wear Compose M3 1.7 needs compileSdk 37
  and AGP ≥ 9.1.
- `versionCode` starts at `100_000_001` (unique across the listing — see [release.md](../release.md)).

## Building watch UI

- **Wear Compose Material 3 only** (`androidx.wear.compose:compose-material3`, `compose-foundation`) — never phone
  Material 3 components. One `AppScaffold` at the app level, a `ScreenScaffold` per screen, `TransformingLazyColumn`
  for lists, `EdgeButton` for the primary action. Wear M3 has no light color scheme; dynamic color on Wear OS 6+.
- **Navigation**: `androidx.wear.compose:compose-navigation3` with `rememberSwipeDismissableSceneStrategy()` (swipe
  to dismiss) — keys and entries live inside `:wear` (the watch doesn't reuse phone features).
- **Rotary input** scrolls lists automatically in Wear M3 scaffolds; test on a device for anything custom.
- **Ambient mode**, **tiles** and **Wear widgets** (Glance Wear + Remote Compose, Wear OS 7; keep a tile alongside for
  older watches) — the `wear-compose-m3` and `wear-widgets` skills. Watch faces must use the Watch Face Format.
- **Phone ↔ watch data**: the Data Layer (`com.google.android.gms:play-services-wearable`, in the catalog) — same
  package and signing on both sides; a repository in `:core:data` behind a `:core:domain` interface.

## Skills

`wear-compose-m3` (apps, M3 components, Nav 3, ambient, previews, migration), `wear-widgets` (widgets, tile migration).

## QA

`bash scripts/avd.sh ensure wear` → `wearos_large_round` (Wear OS 7 / API 37). `android run` the `:wear` APK (tiles and
widgets: `android run --type TILE|WEAR_WIDGET`), read it with `android layout`, scroll with
`android input scroll "scrollable=true" --dir=down --until="text=…"` (no rotary input on the emulator), tap with
selectors. Check round-edge clipping in screenshots. Data Layer scenarios need a paired phone emulator.

## Quality

Wear app quality (core): standalone behavior, round-screen layouts, `TimeText`, swipe-to-dismiss, ambient where
relevant, 64-bit, target API — see [quality.md](../quality.md).
