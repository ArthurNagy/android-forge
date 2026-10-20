---
description: Add a new feature — :feature:<name>:api (Nav 3 key) + :feature:<name>:impl (Compose screen, @HiltViewModel Orbit ViewModel, state, Hilt @IntoSet entry builder, strings, tests and phone/tablet screenshots) — and join it to the app.
argument-hint: <feature-name>
---

# /android-forge-add-feature

Scaffolds a complete feature on the locked stack: `:feature:<name>:api` (its Navigation 3 key — what other
features depend on to navigate here) and `:feature:<name>:impl` (everything else, all `internal`). The app
joins it with a single Gradle dependency; its entries reach `NavDisplay` through Hilt multibinding.

## Arguments

Arguments: `$ARGUMENTS`

- **`<feature-name>`**: lowercase kebab-case or a single word (`gallery`, `auth`, `photo-detail`). Module paths
  `:feature:<name>:api|impl`, package `<base>.feature.<pkg>.{api,impl}` where `<pkg>` drops dashes
  (`photodetail`), resource prefix `<name with underscores>_` (`photo_detail_`).

No argument → ask via `AskUserQuestion`. Also ask (one call, skip what the user already said):
1. **Start destination?** — should this feature replace the `Home` placeholder as the launch screen? (Recommended
   for the first feature.)
2. **Key argument?** — does its key carry an ID (`photoId: String`)? Then the ViewModel gets it by assisted injection.

## Flow

1. **Validate** the name (`^[a-z][a-z0-9]*(-[a-z0-9]+)*$`) and that `feature/<name>` doesn't exist.
2. **Base package**: the `**Application ID / base package:**` line of the project `CLAUDE.md`; else `namespace` in
   `app/build.gradle.kts`; else ask.
3. **Delegate** to the `android-forge:android-feature-builder` agent with `feature_name`, `base_package`,
   `project_root` (absolute), `claude_plugin_root` (the absolute value of `${CLAUDE_PLUGIN_ROOT}` — the agent does
   not inherit it), `start_destination` and `key_argument`. It renders both modules from
   `overlay/modules/feature/{api,impl}`, wires a matching `:core:domain` use case if one exists, adds the impl to
   `app/build.gradle.kts` above `// android-forge:feature-modules`, switches the start destination if asked,
   updates `CLAUDE.md`, runs `spotlessApply`, records the screenshot goldens and builds.
4. **Report** what it returns:

```
✓ Added :feature:<name>:api (<Name>Key) + :feature:<name>:impl (screen, ViewModel, state, entries, Hilt entry module, strings, tests)
✓ Joined :app (one dependency line; entries via @IntoSet)<; start destination is now <Name>Key>
✓ Screenshots: feature/<name>/impl/src/test/screenshots/ (phone + tablet) — review them
✓ Build: green | red (with output)

Next: the screen renders a placeholder (TODO(android-forge)) — build the real UI following the presentation-layer
skill; add the use case in :core:domain first if it doesn't exist (domain-layer skill).
Run it: android run --apks=app/build/outputs/apk/debug/app-debug.apk (emulator), or ask for the android-qa agent.
```

## Notes

- The package segment drops dashes (`photodetail`): Kotlin packages can't contain them and ktlint rejects underscores.
  Gradle module paths keep dashes (`:feature:photo-detail:impl`).
- Another feature navigates here by adding `implementation(project(":feature:<name>:api"))` to its impl and pushing
  `<Name>Key` — never by depending on this impl.
- If `:core:domain` has no relevant use case yet, the ViewModel carries a comment showing where to call it.
