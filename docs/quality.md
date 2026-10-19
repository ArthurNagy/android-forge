# Quality tiers

Google publishes a quality bar per form factor. android-forge aims every project at the **first ("ready")
tier** of each form factor it ships, and makes the higher tiers a product decision (an issue, maybe an ADR).
The `android-reviewer` flags code that breaks a "ready" item; the `android-qa` agent checks the user-visible ones
on the form factor's emulator. Sources: Android's quality guidelines (`android docs search "app quality guidelines"`).

| Form factor | Tiers (lowest → highest) | android-forge baseline |
|---|---|---|
| Phones, tablets, foldables, desktop | **Adaptive ready** → Adaptive optimized → Adaptive differentiated | ready (the scaffold's defaults), optimized for screens with list/detail content |
| Googlebook / ChromeOS (desktop experience) | the adaptive tiers + desktop experience items | keyboard/mouse parity on interactive screens |
| Android Auto / Android Automotive OS | **Car ready** → Car optimized → Car differentiated (+ per-category DD-/AN- checks) | ready for the chosen category |
| TV / Google TV | **TV ready** → TV optimized → TV differentiated | ready |
| Wear OS | Wear app quality (core + per-surface: app, tiles/widgets, watch faces) | core |
| Android XR | XR compatible (mobile / large-screen) → XR differentiated | compatible (same APK) |

## Adaptive ready (every project)

- No orientation / resizability / aspect-ratio locks (Android 16 ignores them on sw ≥ 600dp; Android 17 removes the
  opt-out). The reviewer blocks them.
- Layouts adapt to the window, not the device: no letterboxing, no stretched phone UI on tablets; list/detail content
  uses the Nav 3 list-detail scene strategy.
- State survives configuration changes, folding/unfolding, multi-window resizing and process death (Orbit state +
  saveable back stack + the QA background/cold-start check).
- Edge-to-edge with correct insets; predictive back works.
- Touch targets ≥ 48dp; keyboard can reach every interactive element; hover/right-click where it's expected.
- Checked by: phone + tablet Roborazzi goldens (every screen), QA journeys on phone and — for layout changes —
  tablet and foldable AVDs.

## Desktop experience (Googlebook/ChromeOS, opt-in polish)

Keyboard shortcuts (and the Keyboard Shortcuts Helper), scrollbars, hover states, right-click menus, text selection
(double/triple click), multi-instance and multi-window, drag and drop between windows, `touchscreen` not required
in the manifest. See [form-factors/desktop.md](form-factors/desktop.md).

## Car ready / TV ready / Wear core / XR compatible

Each form factor's page lists its ready-tier checklist next to its manifest and module rules:
[cars](form-factors/cars.md) · [tv](form-factors/tv.md) · [wear](form-factors/wear.md) · [xr](form-factors/xr.md) ·
[glasses](form-factors/glasses.md).

## Going higher

Moving to an optimized/differentiated tier is product work: file it as an issue (the `backlog-issue-authoring`
skill), let the architect fit it in, and record the tier you claim in the project's `CLAUDE.md` § Form factors so the
reviewer and QA hold you to it.
