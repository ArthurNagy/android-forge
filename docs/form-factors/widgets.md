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

One edit: `implementation(project(":widget"))` in `app/build.gradle.kts`. The receiver's manifest merges into `:app`.

The template ships `HomeWidget` (`GlanceAppWidget`, `SizeMode.Exact`), the public `HomeWidgetReceiver`, a stateless
`HomeWidgetContent` (Glance `Scaffold` + `TitleBar` + body; tapping opens the app through its launch intent, resolved at
runtime so `:widget` never depends on `:app`), a Glance `@Preview`, `res/xml/widget_home_info.xml` (with
`tools:targetApi="s"` for the Android 12+ attributes), a picker `previewLayout`, strings with the `widget_` prefix, and
`HomeWidgetTest` (`runGlanceAppWidgetUnitTest`).

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
