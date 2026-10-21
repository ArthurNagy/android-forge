# Android XR display and AI glasses (projected)

Glasses apps are **projected from the phone**: a dedicated activity in the phone APK renders on the glasses' display,
built with **Jetpack Compose Glimmer** (not Material). android-forge puts it in a **`:glasses` Android library** linked
into `:app`. (Headsets and wired XR glasses run the 2D/spatial phone app instead — [xr.md](xr.md).)

**Pre-release.** The official docs pin exact alpha versions and say to use them even when newer ones exist; there is
no Play distribution for glasses apps yet.

## Add it

`/android-forge-add-form-factor glasses` (the `android-form-factor-builder` agent):

```bash
FFD="${CLAUDE_PLUGIN_ROOT}/overlay/form-factors/glasses"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render-module glasses "${FFD}/glasses" "${TARGET}/glasses" "${BASE_PACKAGE_PATH}"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-settings "${TARGET}" "glasses"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-libs "${TARGET}" "${FFD}/libs.versions.toml.additions"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" install "${TARGET}" glasses
```

Edits on `:app`: `implementation(project(":glasses"))`, and the phone-side entry point on a surface `:app` owns for
good — `MainActivity`, over the navigation host:

```kotlin
AppTheme(themeMode = state.themeMode) {
    Box(Modifier.fillMaxSize()) {
        AppNavigation(entryProviderInstallers = entryProviderInstallers)
        // :glasses — shown over every screen while display glasses are connected; starts the experience on them.
        LaunchOnGlassesButton(
            modifier = Modifier.align(Alignment.BottomEnd).safeDrawingPadding().padding(AppSpacing.md),
            hideWhileDisconnected = true,
        )
    }
}
```

Not `Home.kt`: a feature that takes over the start destination deletes it, and the entry point would silently go
with it. Hidden while no glasses are connected, it changes no screen's golden. An app-level top bar is the other
good home — there, keep the default `hideWhileDisconnected = false` (a disabled button until glasses connect).
Features never depend on `:glasses`.

The template ships `GlassesActivity` (`GlimmerTheme` with Google Sans Flex), `GlassesHome` (pure black background, a
bottom-aligned `ActionCard` with the app name and a Close button), the public `LaunchOnGlassesButton` (absent below
Android 16, disabled — or with `hideWhileDisconnected`, hidden — until glasses connect, starts the activity on the
glasses' display via `ProjectedContext.createProjectedActivityOptions`; mobile Material 3, since it renders on the
phone), the manifest activity
(`android:requiredDisplayCategory="android.hardware.display.category.XR_PROJECTED"`, `XR_PROJECTED_LAUNCHER` category for
voice launch), strings with the `glasses_` prefix, and tests.

Pins (`libs.versions.toml.additions`): `androidx.xr.runtime` 1.1.0-alpha01, `glimmer` + `glimmer-google-fonts`
1.0.0-alpha18, `projected` 1.0.0-alpha09, `arcore` 1.0.0-beta02 (catalog only). `/android-forge-bump-stack` proposes only
what the current docs pin (`android docs search "glimmer setup"`).

## Building glasses UI

The `display-glasses-with-jetpack-compose-glimmer` skill: Glimmer components only, black backgrounds (they render
transparent), large text (≥ 18sp), focus-driven input (temple touchpad, voice), short glanceable flows. The process-wide
`ComposeUiFlags.isInitialFocusOnFocusableAvailable` the docs mention would also change the phone UI — set it only if
the phone screens are checked with it.

Cost: the XR runtime adds ~0.5 MB of native code per ABI to the phone APK, and `projected` brings in appcompat.

## QA

`bash scripts/avd.sh ensure glasses` → `ai_glasses_device` (`android-36/ai-glasses`). It runs only paired with a host
phone AVD (the docs: a phone on the **API CANARY** 16 KB page-size Play image), and the pairing is a UI flow —
Android Studio Canary's Device Manager → **Pair Glasses** (Pairing Assistant), or the Glasses app on the phone
(`android docs fetch kb://android/develop/xr/jetpack-xr-sdk/run/create-avds/glasses`). `avd.sh` can't create the host
or pair them, so the `android-qa` agent treats glasses like Android Auto: it runs glasses journeys only on a pair the
human has paired and started; otherwise those scenarios are verified by hand (paired emulators reconnect on every
later launch). android-forge's own validation of this template was build and Robolectric only (the activity launches,
the home renders, the launch button's three states).

## Quality

Google hasn't published quality guidelines for display glasses yet (the XR quality page marks them "stay tuned"), and
there's no Play distribution. Until then android-forge holds glasses UI to the official glasses docs and the
`display-glasses-with-jetpack-compose-glimmer` skill:
- **Display**: Jetpack Compose Glimmer components only; pure black backgrounds (an additive display renders black as
  transparent); one glanceable thing at a time, large text.
- **Capabilities**: check `ProjectedDeviceController` before showing visual UI — audio glasses have no display — and
  follow the display turning off (`ProjectedDisplayController`) with an audio path.
- **Input**: focus-driven (temple touchpad) with a sensible initial focus; voice launch through the
  `XR_PROJECTED_LAUNCHER` activity's label; always a way out (Close).
- **Permissions**: glasses hardware (camera, microphone) through `ProjectedPermissionsResultContract`, requested in
  the projected context.
- **Phone side**: the entry point exists only where projection does (Android 16+), starts on the glasses' display —
  never the phone — and is unusable or hidden while no glasses are connected. The phone app itself stays Adaptive
  ready ([quality.md](../quality.md#adaptive-ready-every-project)).
