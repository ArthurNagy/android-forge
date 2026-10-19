# Android XR display and AI glasses (projected)

Glasses apps are **projected from the phone**: a dedicated activity in the phone APK renders on the glasses' display,
built with **Jetpack Compose Glimmer** (not Material). android-forge puts it in a **`:glasses` Android library** linked
into `:app`. (Headsets and wired XR glasses run the 2D/spatial phone app instead — [xr.md](xr.md).)

**Pre-release.** The official docs pin exact alpha versions and say to use them even when newer ones exist; there is
no Play distribution for glasses apps yet.

## Add it

```bash
FFD="${CLAUDE_PLUGIN_ROOT}/overlay/form-factors/glasses"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render-module glasses "${FFD}/glasses" "${TARGET}/glasses" "${BASE_PACKAGE_PATH}"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-settings "${TARGET}" "glasses"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-libs "${TARGET}" "${FFD}/libs.versions.toml.additions"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" install "${TARGET}" glasses
```

Edits on `:app`: `implementation(project(":glasses"))`, and place `LaunchOnGlassesButton()` on a surface `:app` owns
(the start screen, a top bar). Features never depend on `:glasses`.

The template ships `GlassesActivity` (`GlimmerTheme` with Google Sans Flex), `GlassesHome` (pure black background, a
bottom-aligned `ActionCard` with the app name and a Close button), the public `LaunchOnGlassesButton` (absent below
Android 16, disabled until glasses connect, starts the activity on the glasses' display via
`ProjectedContext.createProjectedActivityOptions`), the manifest activity
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

`bash scripts/avd.sh ensure glasses` → `ai_glasses_device` (`android-36/ai-glasses`), which pairs with a phone AVD on a
CANARY 16 KB image — a heavy setup; android-forge's own validation of this template was build-only. Tests run under
Robolectric (the activity launches, the home renders).
