---
description: Add a device type or surface to an android-forge project — Wear OS, TV, Android Auto, Android Automotive OS, XR headset, XR display glasses, Googlebook/desktop, Google Cast or home-screen widgets — with its module or manifest pieces, catalog entries, Android skill tier, emulator and docs.
argument-hint: <wear|tv|auto|automotive|xr|glasses|desktop|cast|widgets>
---

# /android-forge-add-form-factor

Adds one form factor to an existing android-forge project (also run by `/android-forge-init` for the ones picked at
scaffold time). Phones, tablets and foldables are always in — they are the adaptive `:app`.

| Form factor | Lands as | Emulator |
|---|---|---|
| `desktop` (Googlebook / ChromeOS) | `:app` manifest + adaptive polish (same APK) | `desktop_medium` |
| `xr` (headset) | `:app` manifest (same APK; spatial UI later) | `xr_headset_device` |
| `glasses` (XR display / AI glasses) | `:glasses` library linked into `:app` (projected activity) | `ai_glasses_device` + paired phone |
| `widgets` | `:widget` library linked into `:app` (Glance) | the phone |
| `auto` (Android Auto) | `:car` library linked into `:app` (Car App Library) | Desktop Head Unit (manual) |
| `automotive` (AAOS) | `:automotive` app module + `:car` | `automotive_1408p_landscape_with_play` |
| `tv` | `:tv` app module (Compose for TV) | `tv_1080p` |
| `wear` | `:wear` app module (Wear Compose Material 3) | `wearos_large_round` |
| `cast` (sender) | catalog + skill only — the first media slice builds `:core:media` | real Cast device |

`auto` and `automotive` share `:car`; adding the second reuses it.

## Arguments

`<form-factor>` — one of the above. Missing → ask via `AskUserQuestion`. For `auto` / `automotive` also ask the **car
app category** (unless `:car` already exists): templated — `poi`, `iot`, `weather`, `navigation`, `messaging`
(Car App Library); `media` (Media3 `MediaLibraryService`, no `:car`); `parked` (video / games / browser running while
parked). Templated categories render `:car`; media and parked follow the recipes in `docs/form-factors/cars.md`.

## Flow

1. **Read the project**: `CLAUDE.md` (base package, form factors already present, minSdk), `settings.gradle.kts`.
   Refuse a form factor that is already there (say what exists).
2. **Delegate** to the `android-forge:android-form-factor-builder` agent with `form_factor`, `project_root`
   (absolute), `base_package`, `claude_plugin_root` (the absolute value of `${CLAUDE_PLUGIN_ROOT}` — the agent does not
   inherit it) and, for cars, `car_app_category`. It renders the templates from `overlay/form-factors/<ff>/`, patches
   the catalog and settings, edits `:app` where needed, installs the form factor's Android skill tier, updates
   `CLAUDE.md` § Form factors, runs the gate, and reports.
3. **Emulator** — ask via `AskUserQuestion` whether to create the form factor's emulator now (it downloads a system
   image, often 1–4 GB). On yes:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/avd.sh" ensure <form-factor>
   android emulator start "$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/avd.sh" name <form-factor>)"
   ```
   then install and launch the module's debug APK (`android describe` lists it) and show the user a screenshot.
4. **Report**:

```
✓ Added <form factor>: <modules / manifest changes>
✓ Catalog: <keys> · Android skills: <tier> installed in .claude/skills/
✓ CLAUDE.md § Form factors updated
✓ Gate: green | red (output)
✓ Emulator: <AVD> created/started, screenshot <path> | skipped (run: bash <plugin>/scripts/avd.sh ensure <ff>)

Next: <form-factor-specific next step — e.g. Wear: build the watch UI with the wear-compose-m3 skill; TV: D-pad
focus paths; cars: the category's quality checklist> — docs/form-factors/<ff>.md
```

## Notes

- Form-factor app modules (`:wear`, `:tv`, `:automotive`) share the `applicationId`, depend on
  `:core:model`/`:core:domain`/`:core:data`, and never on phone UI modules. They ship to their own Play track.
- Each form factor has a quality tier to meet — see `docs/quality.md` and its page under `docs/form-factors/`.
