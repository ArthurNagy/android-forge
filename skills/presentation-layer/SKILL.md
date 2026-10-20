---
name: presentation-layer
description: This skill should be used in an android-forge project (its CLAUDE.md says "android-forge project rules") when building or changing a Compose screen, a @HiltViewModel Orbit ViewModel or its state, Nav 3 keys/entries or navigation between features, a phone/tablet list-detail layout, strings and error wording, a :core:designsystem token or shared composable, or their ViewModel/screen/Roborazzi tests — or when an OpenSpec task touches :feature:*, :core:ui or :core:designsystem. It supplies android-forge's conventions (state-only consumable slots, Hilt @IntoSet entries, @AssistedInject key arguments, prefixed strings, a11y/RTL); Google's navigation-3, adaptive and edge-to-edge skills cover the platform APIs.
---

# Presentation (`:feature:*` and `:core:ui` / `:core:designsystem`) — android-forge style

A feature is presentation only: its `:api` module holds its Nav 3 keys; its `:impl` module holds screens,
ViewModels, state, strings and the entry builder that contributes its screens to the app. Business logic
comes from `:core:domain` use cases (the `domain-layer` skill). Canonical rules: the plugin's
[architecture.md](../../docs/architecture.md) (§ `:feature:<name>:impl`, § ViewModel + Orbit, § Navigation
wiring, § Visibility), [stack.md](../../docs/stack.md), [i18n-a11y.md](../../docs/i18n-a11y.md),
[testing.md](../../docs/testing.md). Google's `adaptive`, `navigation-3`, `navigation-event` and
`edge-to-edge` skills (installed in the project) go deeper on their topics — load them for that work.

## Start from the generators

- New feature: `/android-forge-add-feature <name>`; new screen in a feature: `/android-forge-add-screen <feature> <screen>`.
  They render the templates and add the one app dependency. This skill is about filling them in.
- A feature `impl` depends on `:core:domain`, `:core:model`, `:core:ui`, `:core:designsystem`, `:core:navigation`
  (the `android-forge.feature.impl` convention adds them) and other features' `:api` — never `:core:data` or
  another feature's `impl`.

| Lives in | What |
|---|---|
| `:feature:<name>:api` | `@Serializable` keys (`data object GalleryKey : NavKey`, `data class PhotoDetailKey(val photoId: String) : NavKey`) |
| `:feature:<name>:impl` | **all internal:** `XScreen` + `XContent`, `XViewModel`, `XState`, `xEntries(navigator)`, `XEntryModule` (`@IntoSet`); strings with the module's `resourcePrefix` |
| `:core:designsystem` | `AppTheme`, color schemes, `AppType`/`AppSpacing`/`AppDimens`, stateless components |
| `:core:ui` | `DomainError.toMessage()`, shared labels (`core_ui_navigate_back`), composables two features share |
| `:core:navigation` | the `Navigator` class, `EntryProviderInstaller` (the `@Multibinds` set) |
| `:app` | the back stack, the `Navigator` instance, `NavDisplay` with scene strategies; never lists features |

Form-factor app modules (`:wear`, `:tv`) follow the same ViewModel, Orbit and state rules; their UI, navigation and
goldens follow `docs/form-factors/<ff>.md` and Google's form-factor skill (`wear-compose-m3`, Compose for TV) instead
of the list-detail and phone/tablet golden rules here. `:car` screens are Car App Library templates, not Compose.

## Recipes

Each recipe — the compiling example plus its rules — is a file in `references/` next to this one; read the ones the
task needs (when reading this file directly instead of invoking the skill, they are under
`<claude_plugin_root>/skills/presentation-layer/references/`). A new screen usually takes them in this order:

- [State](references/state.md) — `XState`: consumable slots (`pendingNavigation`, `@StringRes pendingMessage`),
  `Initial`, no constructor defaults, when a sealed page state fits.
- [ViewModel](references/viewmodel.md) — `@HiltViewModel` + Orbit state-only, work in the on-create block, intents
  over use cases, `onXConsumed()`, key arguments with `@AssistedInject`.
- [Screen and Content](references/screen-and-content.md) — `XScreen` (ViewModel default parameter, one
  `LaunchedEffect` per slot through `rememberUpdatedState`) and stateless `XContent`; which navigation path; insets.
- [Navigation 3](references/navigation.md) — keys in `:api`, `entry<Key>` builders, the `@IntoSet` module, navigating
  to another feature, `backOrNull()`, becoming the start destination.
- [Strings and errors](references/strings-and-errors.md) — prefixed string resources, wording `DomainError` (typed
  errors first, `toMessage()` / `messageRes()` fallback), plurals, the template placeholder.
- [Tests](references/tests.md) — ViewModel tests over real use cases and fakes, Robolectric screen tests, Roborazzi
  phone + tablet (+ RTL) goldens, `// Scenario:` tags.

## Adaptive layouts (phones, foldables, tablets, desktop)

- **List-detail**: mark entries `ListDetailSceneStrategy.listPane()` / `detailPane()` (`extraPane()`); `:app`'s
  `NavDisplay` already uses `rememberListDetailSceneStrategy()`. Never `ListDetailPaneScaffold`.
- **Within a screen**, branch on the window, not the device: `currentWindowAdaptiveInfo().windowSizeClass`
  (`isWidthAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND)`), adaptive grids
  (`LazyVerticalGrid(GridCells.Adaptive(minSize = …))`), max content widths on wide windows.
- Never lock orientation or resizability; support keyboard/mouse (focus, hover, right-click) where the screen
  is interactive — required on Googlebook/desktop. The `adaptive` skill covers MediaQuery, Grid/FlexBox and
  input-device handling in depth.
- Screenshot every screen on a phone **and** a tablet ([Tests](references/tests.md)).

## Composables, accessibility, RTL

- Sizes and gaps from `AppSpacing` / `AppDimens`; colors from `MaterialTheme.colorScheme`; text from
  `MaterialTheme.typography`. No `.sp` literals, no color literals outside `:core:designsystem`.
- `Icon` / `Image` / `AsyncImage` always pass `contentDescription` (a string resource, or an explicit `null` when decorative).
- Touch targets ≥ 48dp (`Modifier.minimumInteractiveComponentSize()` on custom clickables).
- RTL: `padding(start = …, end = …)`, `Alignment.Start` / `End` — never `left` / `right` / `absoluteOffset`.
- `Modifier.testTag("<screen>:<element>")` on every element a test or a QA journey must find.
- Every composable that emits UI takes `modifier: Modifier = Modifier` as its first optional parameter
  (compose-rules).

## Before you hand it on

- The impl exposes nothing public; keys are in `:api`; no `:core:data` import; no other feature's `impl`.
- No `postSideEffect`, no `try/catch` in an intent, no `Dispatchers.*`, no repository or Navigator in a ViewModel;
  work starts in the on-create block.
- `State` has no defaults; every `pendingX` slot has its `LaunchedEffect` and `onXConsumed()`.
- An assisted ViewModel's screen takes it as a required parameter; outcome-dependent navigation goes through a slot.
- Strings are prefixed and in `values/strings.xml`; the placeholder is gone; the accessibility checklist holds.
- Phone + tablet goldens recorded and reviewed.
- `./gradlew :feature:<name>:impl:testDebugUnitTest` while iterating; before pushing `./gradlew spotlessApply`, then
  `./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true` (85% line coverage).
  User-visible change → ask for the `android-qa` agent.
