# Phones, tablets and foldables (default)

Every android-forge project targets phones, tablets and foldables with **one adaptive `:app`** — and, through the
same APK, Googlebook/ChromeOS desktops ([desktop.md](desktop.md)) and XR headsets as 2D panels ([xr.md](xr.md)).

## What the scaffold already does

- `enableEdgeToEdge()` in `MainActivity`; screens use `Scaffold` insets.
- `AppNavigation` uses Nav 3 with `rememberListDetailSceneStrategy()`: entries marked
  `ListDetailSceneStrategy.listPane()` / `detailPane()` show side by side on wide windows, one at a time on compact ones.
- No orientation or resizability locks anywhere (and the reviewer blocks new ones).
- Every screen gets phone + tablet Roborazzi goldens; QA runs layout changes on phone, tablet and foldable AVDs.

## Building adaptive screens

- Branch on the **window**, never the device: `currentWindowAdaptiveInfo().windowSizeClass`
  (`isWidthAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND)` / `…EXPANDED…`), or the Compose
  MediaQuery API the `adaptive` skill describes (`windowWidth`, `windowPosture`, `pointerPrecision`, `keyboardKind`;
  experimental — check its flag with `android docs search "mediaquery"`).
- Lists: `LazyVerticalGrid(GridCells.Adaptive(minSize = …))`; cap reading widths on wide windows.
- Navigation chrome: `NavigationSuiteScaffold` (bar on compact, rail on medium/expanded) around `NavDisplay` once the
  app has top-level destinations; multiple back stacks per the `navigation-3` skill.
- Supporting panes: `SupportingPaneSceneStrategy` (same metadata pattern) — never `ListDetailPaneScaffold` /
  `SupportingPaneScaffold` directly.
- Foldables: test the posture (`windowPosture` — tabletop/book) only when the design uses it; hinge-aware layouts are
  "differentiated", not required.
- Input: every interactive element reachable by keyboard (Tab/arrows/Enter), hover feedback on pointer devices.

## Android version behavior

Android 16 (API 36) ignores `screenOrientation`, `resizeableActivity`, `min/maxAspectRatio` and
`setRequestedOrientation` on displays ≥ 600dp; Android 17 (API 37, android-forge's targetSdk) removes the temporary
opt-out. Exceptions: games (`android:appCategory="game"`), user opt-in, small screens.

## Skills

`adaptive` (window size, MediaQuery, Grid/FlexBox, input devices, Nav 3 scenes), `navigation-3`, `edge-to-edge`,
`navigation-event` (predictive back) — all in the baseline tier.

## QA

`medium_phone`, `medium_tablet` (Android CLI profiles) and `pixel_10_pro_fold` (avdmanager) — `scripts/avd.sh ensure
phone|tablet|foldable`. On the foldable, screenshots need the multi-display fix-up (see [android-cli.md](../android-cli.md)).

## Quality

Adaptive ready — the checklist (configuration continuity, multi-window, keyboard/mouse/stylus basics) is in
[quality.md](../quality.md#adaptive-ready-every-project), the one place it lives.
