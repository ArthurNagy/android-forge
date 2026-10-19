# Android XR headsets (and wired XR glasses)

Android XR runs the phone APK: there is no `:xr` module and no separate Play track in android-forge's shape.
Sources: `android docs fetch kb://android/develop/xr/check-mobile-app-readiness`,
`kb://android/docs/quality-guidelines/android-xr/index`, `kb://android/develop/xr/jetpack-xr-sdk/build-immersive`,
`kb://android/develop/xr/jetpack-xr-sdk/add-xr-to-existing`, `kb://android/develop/xr/jetpack-xr-sdk/set-up-sdk`,
`kb://android/develop/xr/package-and-distribute`. Skill: `adaptive` (`scripts/skills.sh` tier `xr`).
Display/AI glasses (projected, Glimmer) are a different form factor: [glasses.md](glasses.md).

Added by `/android-forge-add-form-factor xr`: the manifest line below (`overlay/form-factors/xr/app-manifest-snippet.xml`),
the `xr` skill tier (`adaptive`), and the form-factor line in `CLAUDE.md`.

## Tier 1 — "Android XR compatible" (every android-forge app, nothing to add)

A mobile or large-screen app is automatically available on XR headsets, shown as a 2D panel in Home Space,
**as long as it requires no feature XR devices lack** (telephony, camera with autofocus, GPS…). No dependency,
no manifest change. What makes it a *good* panel is adaptive quality (aim for adaptive Tier 2 — the
`android-forge` defaults: no orientation/resizability locks, window-size layouts with Nav 3 list-detail
scenes, keyboard/mouse input, config-change continuity, larger touch targets).

Check: `aapt2 dump badging app/build/outputs/apk/debug/app-debug.apk | grep uses-feature` — every line must be
`uses-feature-not-required`, except `android.hardware.faketouch` (implied).

## The manifest line

`overlay/form-factors/xr/app-manifest-snippet.xml` → a direct child of `<manifest>` in `app/src/main/AndroidManifest.xml`:

```xml
<uses-feature
    android:name="android.software.xr.api.spatial"
    android:required="false" />
```

Required by the docs as soon as `:app` contains Jetpack XR SDK code (tier 2) and ships on the mobile track;
harmless (and future-proof) before that. `required="true"` only belongs in a separate APK on Play's dedicated
Android XR track — never in `:app`.

## Tier 2 — "Android XR differentiated" (opt-in, documented here, not templated)

At least one XR-specific feature: spatial panels, orbiters, an environment, 3D content, spatial audio.
Minimal code path: move the app's UI into a movable, resizable spatial panel when spatial UI is on, and keep
the 2D UI everywhere else.

1. Catalog (pre-release — use the versions `set-up-sdk` lists for immersive experiences at the time; checked
   2026-10-19, compiled against `:app`):
   ```toml
   [versions]
   androidxXrRuntime = "1.1.0-alpha01"     # shared with the glasses form factor
   androidxXrScenecore = "1.0.0-rc01"
   androidxXrCompose = "1.0.0-beta01"
   [libraries]
   androidx-xr-runtime = { module = "androidx.xr.runtime:runtime", version.ref = "androidxXrRuntime" }
   androidx-xr-scenecore = { module = "androidx.xr.scenecore:scenecore", version.ref = "androidxXrScenecore" }
   androidx-xr-compose = { module = "androidx.xr.compose:compose", version.ref = "androidxXrCompose" }
   ```
   `:app`: `implementation(libs.androidx.xr.runtime)`, `implementation(libs.androidx.xr.scenecore)`,
   `implementation(libs.androidx.xr.compose)`. Release builds run R8: also
   `compileOnly("com.android.extensions.xr:extensions-xr:1.3.0")` (docs: required for minified builds; must be
   `compileOnly`). Optional: `androidx.xr.compose.material3:material3` (XR-aware `NavigationSuiteScaffold`).
2. `:app` — wrap the navigation host:
   ```kotlin
   import androidx.xr.compose.platform.LocalSpatialCapabilities
   import androidx.xr.compose.spatial.Subspace
   import androidx.xr.compose.subspace.SpatialPanel
   import androidx.xr.compose.subspace.layout.SubspaceModifier
   import androidx.xr.compose.subspace.layout.movable
   import androidx.xr.compose.subspace.layout.resizable

   /** In Full Space the app's UI moves into a spatial panel; everywhere else (phones, Home Space) it renders as is. */
   @Composable
   internal fun SpatialAppContent(content: @Composable () -> Unit) {
       if (LocalSpatialCapabilities.current.isSpatialUiEnabled) {
           Subspace { SpatialPanel(SubspaceModifier.movable().resizable()) { content() } }
       } else {
           content()
       }
   }
   // MainActivity: AppTheme(...) { SpatialAppContent { AppNavigation(...) } }
   ```
   Branch on capabilities (`LocalSpatialCapabilities.current.isSpatialUiEnabled` / `isSpatialAudioEnabled`),
   never on device type. Next steps the docs list: a Home Space ↔ Full Space toggle (required by the quality
   guidelines once you go Full Space), `Orbiter` around the `NavigationRail`, `SpatialDialog`/`SpatialPopup`
   instead of `Dialog`/`Popup`, `SpatialElevation`. Optional application `<property>`s:
   `android.window.PROPERTY_XR_ACTIVITY_START_MODE` (`XR_ACTIVITY_START_MODE_HOME_SPACE` |
   `XR_ACTIVITY_START_MODE_FULL_SPACE_MANAGED`) and `android.window.PROPERTY_XR_BOUNDARY_TYPE_RECOMMENDED`.
3. Tests: the composable takes the 2D branch under Robolectric (no spatial capabilities), so existing screen
   tests and goldens stay valid; check the spatial branch on the emulator.

## QA

- Emulator: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/avd.sh" ensure xr` (large download), then
  `android emulator start "$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/avd.sh" name xr)"` and
  `android run --apks=app/build/outputs/apk/debug/app-debug.apk --device=<serial>`. The same APK as the phone.
- Verify: launches as a panel, resizes without losing state (scroll position, input), keyboard and pointer
  work, nothing clipped at the window edges; in tier 2, the panel moves/resizes in Full Space.
- Play: same package, mobile track; make sure the app isn't opted out of XR in the Play Console.

## Quality

XR compatible (mobile / large-screen app) by default; XR differentiated is product work — see [quality.md](../quality.md).
