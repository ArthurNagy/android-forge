# Home-screen widgets (Glance)

A **`:widget` Android library** linked into `:app` — Jetpack Glance (`androidx.glance:glance-appwidget`). Widgets
also show on the Googlebook desktop. (Wear OS widgets are different: Glance Wear + Remote Compose, see [wear.md](wear.md).)

## Add it

```bash
FFD="${CLAUDE_PLUGIN_ROOT}/overlay/form-factors/widgets"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" render-module widget "${FFD}/widget" "${TARGET}/widget" "${BASE_PACKAGE_PATH}"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-settings "${TARGET}" "widget"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-libs "${TARGET}" "${FFD}/libs.versions.toml.additions"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" install "${TARGET}" widgets
```

One edit: `implementation(project(":widget"))` after the `:core:navigation` line in `app/build.gradle.kts`. The
receiver's manifest merges into `:app`.

The template ships `HomeWidget` (`GlanceAppWidget`, `SizeMode.Exact`), the public `HomeWidgetReceiver`, a stateless
`HomeWidgetContent` (Glance `Scaffold` + `TitleBar` + body; tapping opens the app through its launch intent, resolved at
runtime so `:widget` never depends on `:app`), a Glance `@Preview`, `res/xml/widget_home_info.xml` (the Android 12+
attributes with `tools:ignore="UnusedAttribute"` — `tools:targetApi="s"` would fail Lint's `ObsoleteSdkInt` from minSdk
31), a picker `previewLayout` (Android 12+) and a static
`previewImage` (`widget_home_preview_image`, for older pickers — replace it with an image of the real widget),
strings with the `widget_` prefix, and `HomeWidgetTest` (`runGlanceAppWidgetUnitTest`).

## Building widgets

- Follow the `glance-canonical-layouts` skill's layouts (check list, image grid, snap scrolling, toolbar); size with
  `SizeMode.Exact` or `Responsive`, design for the smallest cell first, long-text truncation.
- Data: read domain state through an `@EntryPoint` (Glance widgets aren't Hilt entry points) or update from a worker;
  refresh with `HomeWidget().updateAll(context)` when the data changes.
- Glance pulls in WorkManager, which adds `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE` and
  `ACCESS_NETWORK_STATE` to `:app`'s merged manifest — expect them in the Play data-safety review.
- Generated picker previews (Android 15+) need `providePreview` + `GlanceAppWidgetManager.setWidgetPreviews`
  (rate-limited) — add when the static preview isn't enough.

## Skills

`glance-canonical-layouts`.

## QA

The phone emulator. The Android CLI has no long-press, so placing the widget on the home screen is a manual step; the
automated checks are the Glance unit tests and the merged manifest (`./gradlew :app:processDebugMainManifest`, then look
for `HomeWidgetReceiver`). Once placed, `android layout` reads the widget's content.

## Quality

Google's widget checklists have three tiers — **Tier 3 Low quality** → **Tier 2 Standard** → Tier 1 Differentiated
(`android docs fetch kb://android/docs/quality-guidelines/widget-quality`). android-forge ships widgets at **Standard**;
Differentiated (featured, hero widgets) is product work. ✓ = the template meets it; the rest is the product's:
- Never low quality: `WL-1`/`WL-1.1` fills the launcher grid cell, touching at least two opposing edges ✓ (Glance
  `Scaffold`) · `WC-3` text and icons meet contrast (`GlanceTheme` colors) ✓ · `WD-4.2` the widget's name is in its
  design (the `TitleBar`) ✓ · `WD-4.3` a preview image ✓ · `WT-3`/`WT-3.1`/`WT-3.2` content never stale — update
  (`HomeWidget().updateAll(context)`) after an action in the widget and after a related action in the app · `WT-4`
  nothing cropped or broken at any supported size.
- Standard: `WL-1`/`WL-1.2` aligned with other home-screen elements, no wasted space ✓ · `WL-4`/`WL-4.1` a minimum and
  a maximum resize size ✓ (`widget_home_*_resize_*`; lower the maximum when growing only adds blank space) · `WL-4.2`
  the minimum size still offers value and 48×48dp touch targets ✓ · `WD-4` an accurate picker preview — the
  `previewLayout` ✓, but `widget_home_preview_image` is a placeholder: replace it with an image of the real widget ·
  `WT-1` intentional zero / empty / signed-out states · `WT-2` a manual refresh when users expect fresher data than
  the UI shows.
- Differentiated (product work): `WL-1.1` all four edges · `WL-2` resizes to 2×2, 4×1 or 4×2 · `WL-3` a consistent
  header · `WC-1`/`WC-2` dynamic color, light and dark · `WD-1`/`WD-4.4`/`WD-4.5` a themed preview with user content, a
  descriptive name and description · `WS-2`…`WS-5` the system corner radius, loading state, configuration and launch
  transition.
