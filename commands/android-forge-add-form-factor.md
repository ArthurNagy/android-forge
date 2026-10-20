---
description: Add a device type or surface — Wear OS, TV, Android Auto/AAOS, XR headset or glasses, desktop, Cast, widgets — with its module, catalog, skills and emulator.
argument-hint: <wear|tv|auto|automotive|xr|glasses|desktop|cast|widgets>
---

# /android-forge-add-form-factor

Adds one form factor to an existing android-forge project (also run by `/android-forge-init` for the ones picked at
scaffold time). Phones, tablets and foldables are always in — they are the adaptive `:app`.

| Form factor | Lands as | Emulator |
|---|---|---|
| `desktop` (Googlebook / ChromeOS) | `:app` manifest + adaptive polish (same APK) | `desktop_medium` |
| `xr` (headset) | `:app` manifest (same APK; spatial UI later) | `xr_headset_device` |
| `glasses` (XR display / AI glasses) | `:glasses` library linked into `:app` (projected activity) | `ai_glasses_device` + a host phone, paired in Android Studio |
| `widgets` | `:widget` library linked into `:app` (Glance) | the phone |
| `auto` (Android Auto) | `:car` library linked into `:app` (Car App Library) | Desktop Head Unit (manual) |
| `automotive` (AAOS) | `:automotive` app module + `:car` | `automotive_1408p_landscape_with_play` |
| `tv` | `:tv` app module (Compose for TV) | `tv_1080p` |
| `wear` | `:wear` app module (Wear Compose Material 3) | `wearos_large_round` |
| `cast` (sender) | catalog + skill only — the first media slice builds `:core:media` | real Cast device |

`auto` and `automotive` share `:car`; adding the second reuses it.

## Arguments

Arguments: `$ARGUMENTS`

`<form-factor>` — one of the above. Missing → ask via `AskUserQuestion`, which takes at most 4 options per question:
first **Kind** — Wear OS · TV · Cars · Other surface; then Cars → Android Auto · Android Automotive OS, Other
surface → XR headset · Display glasses · Desktop · Widgets (`cast` arrives through the free-text "Other").
For `auto` / `automotive` also ask the **car app category** (unless `settings.gradle.kts` already includes `:car` —
then its manifest's category stands), in two questions: kind — Templated (Car App Library) · Media (Media3
`MediaLibraryService`, no `:car`) · Parked (video / games / browser running while parked); Templated → `poi` · `iot` ·
`weather` · `navigation`. Templated **messaging** (through "Other") is Android Auto only — a labs category Google
publishes to internal and closed testing tracks only: accept it for `auto`; for `automotive` say so and ask again.
Templated categories render `:car`; media and parked follow the recipes in
`${CLAUDE_PLUGIN_ROOT}/docs/form-factors/cars.md`.

## Flow

1. **Read the project**: `CLAUDE.md` for the base package and app name. Whether the form factor is already there is
   decided from the project itself — `settings.gradle.kts` for the module ones, `:app`'s manifest for `desktop`/`xr`,
   the catalog for `cast` — by the builder, which stops and says what exists.
2. **Delegate** to the `android-forge:android-form-factor-builder` agent with `form_factor`, `project_root`
   (absolute), `base_package`, `app_name`, `claude_plugin_root` (the absolute value of `${CLAUDE_PLUGIN_ROOT}` — the
   agent does not inherit it) and, for cars, `car_app_category`. It renders the templates from
   `overlay/form-factors/<ff>/`, patches the catalog and settings, edits `:app` where needed, installs the form
   factor's Android skill tier, adds its `CLAUDE.md` lines (once), records the new module's goldens, runs the gate,
   and reports.
3. **Emulator** — the `avd.sh` form factor is the argument itself, except `widgets` → `phone`; skip this step for
   `auto` (Desktop Head Unit, manual — print the steps from `${CLAUDE_PLUGIN_ROOT}/docs/form-factors/cars.md`) and
   `cast` (real hardware). `glasses`: `ensure` creates only the glasses AVD — it runs paired with a host phone AVD,
   which Android Studio's Pairing Assistant sets up (print the steps from
   `${CLAUDE_PLUGIN_ROOT}/docs/form-factors/glasses.md`).
   Ask via `AskUserQuestion` whether to create the emulator now (it downloads a system image, often 1–4 GB). On yes:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/avd.sh" ensure <avd-form-factor>
   android emulator start "$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/avd.sh" name <avd-form-factor>)"
   ```
   then install and launch the module's debug APK (`android describe` lists it) and show the user a screenshot.
4. **Report**:

```
✓ Added <form factor>: <modules / manifest changes>
✓ Catalog: <keys> · Android skills: <tier> installed in .claude/skills/
✓ CLAUDE.md § Form factors updated
✓ Gate: green | red (output)
✓ Emulator: <AVD> created/started, screenshot <path> | skipped (run: bash <plugin>/scripts/avd.sh ensure <avd-form-factor>) | none (auto: the Desktop Head Unit · cast: a real Cast device)

Next: <form-factor-specific next step — e.g. Wear: build the watch UI with the wear-compose-m3 skill; TV: D-pad
focus paths; cars: the category's quality checklist> — https://github.com/arthurnagy/android-forge/blob/main/docs/form-factors/<page>
```

`<page>` is `<form factor>.md`, except `auto` / `automotive` → `cars.md`.

## Notes

- Form-factor app modules (`:wear`, `:tv`, `:automotive`) share the `applicationId`, never depend on phone UI
  modules or mobile Material 3, and ship to their own Play track. `:wear` and `:tv` depend on
  `:core:model`/`:core:domain`/`:core:data`; `:automotive` links only `:car` until a car screen shows app data.
- minSdk: the project's (29 or higher), except `:wear` (at least 30, Wear OS 3) and `:automotive` (at least 29). TV
  ready wants 31 or lower — the builder warns when the project's is higher.
- Each form factor has a quality tier to meet — the checklist is in the Quality section of its page under
  `${CLAUDE_PLUGIN_ROOT}/docs/form-factors/` (the tiers overview: `${CLAUDE_PLUGIN_ROOT}/docs/quality.md`).
