# Quality tiers

Google publishes a quality bar per form factor. android-forge aims every project at the tier Google Play requires
for each form factor it ships — the first ("ready") tier, except where Play asks for more (templated car apps must be
**Car optimized**) — and makes the higher tiers a product decision (an issue, maybe an ADR). The `android-reviewer`
flags code and manifests that break a required item; the `android-qa` agent checks the user-visible ones on the form
factor's emulator. Sources: Android's quality guidelines (`android docs search "app quality guidelines"`, then
`android docs fetch kb://android/docs/quality-guidelines/<area>`).

| Form factor | Tiers (lowest → highest) | android-forge baseline | Checklist |
|---|---|---|---|
| Phones, tablets, foldables | **Adaptive ready** → Adaptive optimized → Adaptive differentiated | ready (the scaffold's defaults), optimized for screens with list/detail content | [below](#adaptive-ready-every-project) |
| Googlebook / ChromeOS (desktop experience) | the adaptive tiers + desktop experience items | Adaptive ready + keyboard/mouse parity on interactive screens | [desktop.md](form-factors/desktop.md#quality) |
| Android Auto / Android Automotive OS | Car ready → **Car optimized** → Car differentiated, filtered by app category | Car optimized for templated (driving) categories — Play's bar; Car ready for parked apps | [cars.md](form-factors/cars.md#quality) |
| TV / Google TV | **TV ready** → TV optimized → TV differentiated | ready | [tv.md](form-factors/tv.md#quality) |
| Wear OS | one Wear app quality checklist (apps, tiles, watch faces) — every applicable item | every applicable app item | [wear.md](form-factors/wear.md#quality) |
| Android XR headsets | **XR compatible** (mobile / large-screen) → XR differentiated | compatible (same APK) | [xr.md](form-factors/xr.md#quality) |
| XR display / AI glasses | none published yet (preview) | android-forge's working bar from the glasses docs | [glasses.md](form-factors/glasses.md#quality) |

The `CLAUDE.md` § Form factors bullet of each form factor names the tier it ships at.

## Adaptive ready (every project)

Google's tier 3 builds on core app quality. What it asks, and how android-forge covers it:

- **Configuration and continuity** — the app fills its window (no letterboxing, no compatibility mode) and keeps
  state through rotation, folding, multi-window resizing and their combinations, and process death: no
  orientation / resizability / aspect-ratio locks (Android 16 ignores them on sw ≥ 600dp; Android 17 removes the
  opt-out — the reviewer blocks them), Orbit state + a saveable back stack, the QA background/cold-start check.
- **Multi-window and multi-resume** — fully functional in split screen; a non-focused app keeps updating and gives
  up the camera/microphone when another app takes them.
- **Camera preview and media projection** (when used) — correct in both orientations, folded and unfolded, and in
  multi-window.
- **Keyboard, mouse, trackpad** — text input from an external keyboard (switching between physical and virtual
  without a relaunch); click and select work with a mouse/trackpad; every interactive element reachable by keyboard.
- **Stylus** — select, scroll and (API 34+) handwrite into text fields.
- android-forge extras that the tier assumes: layouts adapt to the window (Nav 3 list-detail scenes, window size
  classes), edge-to-edge with correct insets, predictive back, touch targets ≥ 48dp.
- Checked by: phone + tablet Roborazzi goldens (every screen), QA journeys on phone and — for layout changes —
  tablet and foldable AVDs.

## Going higher

Moving to an optimized/differentiated tier is product work: file it as an issue (the `backlog-issue-authoring`
skill), let the architect fit it in, and record the tier you claim in the project's `CLAUDE.md` § Form factors so the
reviewer and QA hold you to it.
