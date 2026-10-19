---
name: presentation-layer
description: Write or change UI code in an android-forge project — :feature:<name>:impl screens (stateful Screen with a hiltViewModel() default parameter + stateless internal Content), @HiltViewModel Orbit ViewModels with state-only events (consumable state slots, never postSideEffect) that start their work in the container's on-create block, State without defaults plus Initial, Nav 3 keys in :feature:<name>:api and entry builders contributed with Hilt @IntoSet, cross-feature navigation through other features' api keys, key arguments through @AssistedInject, adaptive layouts (list-detail scene metadata, window size), errors through :core:ui's DomainError.toMessage(), module-prefixed string resources, accessibility and RTL, :core:designsystem tokens, and tests (Orbit harness, Compose UI Test v2, Roborazzi phone + tablet goldens). Use in an android-forge project (its CLAUDE.md says "android-forge project rules") when building or changing a screen, ViewModel, UI state, navigation, a shared composable or design token, or when an OpenSpec task touches :feature:* or :core:ui / :core:designsystem.
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
| `:app` | the back stack, `Navigator`, `NavDisplay` with scene strategies; never lists features |

## State

```kotlin
internal data class GalleryState(
    val loading: Boolean,
    val photos: List<Photo>,
    val error: DomainError?,
    // Consumable slots: set by an intent, cleared by the paired onXConsumed() after the UI acts on them.
    val pendingNavigation: NavKey?,
    @StringRes val pendingMessage: Int?,
) {
    companion object {
        val Initial = GalleryState(loading = false, photos = emptyList(), error = null, pendingNavigation = null, pendingMessage = null)
    }
}
```

- **No constructor defaults.** `Initial` is the single starting value, used by `orbitContainer(...)` and every test.
- `error: DomainError?` carries the error as-is; the screen turns it into words.
- **A slot holds what happened, never resolved text:** a flag, a domain value, a key, or a `@StringRes Int`.
- Mutually exclusive page states (`Loading | Loaded | Error`) → `sealed interface XState` with an explicit
  starting object. Default to the flat data class.
- Everything that must survive process death or that an intent needs goes in `State`; only UI-local details
  (scroll position, an open dropdown) live in `rememberSaveable`/`remember`.

## ViewModel

```kotlin
@HiltViewModel
internal class GalleryViewModel
    @Inject
    constructor(
        private val observePhotos: ObservePhotosUseCase,
        private val refreshPhotos: RefreshPhotosUseCase,
    ) : ViewModel(),
        OrbitContainerHost<GalleryState, GalleryState, Nothing> {
        override val container =
            orbitContainer<GalleryState, Nothing>(GalleryState.Initial) {
                observe()       // once per ViewModel = once per back-stack entry
                refresh()
            }

        private fun observe() =
            intent {
                observePhotos().collect { photos -> reduce { state.copy(photos = photos) } }
            }

        fun refresh() =
            intent {
                reduce { state.copy(loading = true, error = null) }
                refreshPhotos()
                    .onOk { reduce { state.copy(loading = false) } }
                    .onErr { error -> reduce { state.copy(loading = false, error = error) } }
            }

        fun onPhotoClicked(id: PhotoId) = intent { reduce { state.copy(pendingNavigation = PhotoDetailKey(photoId = id.value)) } }

        fun onNavigationConsumed() = intent { reduce { state.copy(pendingNavigation = null) } }
    }
```

- `@HiltViewModel` + `@Inject constructor` + `ViewModel()` + `OrbitContainerHost<S, S, Nothing>` +
  `orbitContainer<S, Nothing>(S.Initial) { … }` (Orbit 12). No base class, no `AndroidViewModel`, no `Context`.
- **Start work in the on-create block** — loads and long-lived observations. A `LaunchedEffect(Unit) { viewModel.load() }`
  would reload every time the user comes back.
- **State-only events.** No `postSideEffect`; a one-shot event is a `pendingX` slot + `fun onXConsumed()`.
- Every state change happens inside `intent { reduce { … } }`.
- The constructor takes **use cases** (+ the key, below). Never a repository, `DispatcherProvider`, or `Navigator`.
- Consume `Result` with `onOk` / `onErr`. No `try/catch` in an intent: use cases don't throw.
- **Key arguments** — assisted injection, so the ViewModel gets its key at construction:
  ```kotlin
  @HiltViewModel(assistedFactory = PhotoDetailViewModel.Factory::class)
  internal class PhotoDetailViewModel
      @AssistedInject
      constructor(
          @Assisted private val key: PhotoDetailKey,
          private val getPhoto: GetPhotoUseCase,
      ) : ViewModel(),
          OrbitContainerHost<PhotoDetailState, PhotoDetailState, Nothing> {
          override val container = orbitContainer<PhotoDetailState, Nothing>(PhotoDetailState.Initial) { load() }
          …
          @AssistedFactory
          interface Factory {
              fun create(key: PhotoDetailKey): PhotoDetailViewModel
          }
      }
  ```

## Screen and Content

```kotlin
@Composable
internal fun GalleryScreen(
    onNavigate: (NavKey) -> Unit,
    onNavigateBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    viewModel: GalleryViewModel = hiltViewModel(),
) {
    val state by viewModel.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val resources = LocalResources.current

    // The effect outlives recompositions: read the latest lambda, not the one it started with.
    val currentOnNavigate by rememberUpdatedState(onNavigate)
    LaunchedEffect(state.pendingNavigation) {
        val key = state.pendingNavigation ?: return@LaunchedEffect
        currentOnNavigate(key)
        viewModel.onNavigationConsumed()
    }
    LaunchedEffect(state.pendingMessage) {
        val message = state.pendingMessage ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(resources.getString(message))
        viewModel.onPendingMessageConsumed()
    }

    GalleryContent(
        state = state,
        snackbarHostState = snackbarHostState,
        onPhotoClick = viewModel::onPhotoClicked,
        onRetry = viewModel::refresh,
        onNavigateBack = onNavigateBack,
        modifier = modifier,
    )
}
```

- `XScreen` takes `viewModel: XViewModel = hiltViewModel()` as a **default parameter** (compose-rules' convention;
  tests pass a ViewModel built outside composition) and `modifier: Modifier = Modifier`.
- One `LaunchedEffect` per consumable slot; **lambda parameters used inside an effect go through
  `rememberUpdatedState`** (compose-rules `lambda-param-in-effect` fails the gate otherwise).
- `XContent` is `internal` and stateless (state + lambdas, no ViewModel, no Hilt) so screen and screenshot tests
  render it with any state. Host the `SnackbarHost` in its `Scaffold`, or `showSnackbar` never returns.
- A tap that only navigates may call the lambda directly; navigation that depends on an outcome goes through
  `pendingNavigation`.
- Edge-to-edge is on (`enableEdgeToEdge()`): use `Scaffold`'s `innerPadding` / `WindowInsets` — never hard-code
  status-bar heights (the `edge-to-edge` skill).

## Navigation 3

- **Keys** live in the feature's `:api`, are `@Serializable`, and carry IDs (the back stack is saved).
- **Entries** (`XEntries.kt`, internal): one `entry<Key> { … }` per screen; the screen gets lambdas, never the Navigator:
  ```kotlin
  @OptIn(ExperimentalMaterial3AdaptiveApi::class)
  internal fun EntryProviderScope<NavKey>.galleryEntries(navigator: Navigator) {
      entry<GalleryKey>(metadata = ListDetailSceneStrategy.listPane()) {
          GalleryScreen(onNavigate = navigator::navigate, onNavigateBack = navigator.backOrNull())
      }
  }
  ```
  A key argument reaches the ViewModel through its factory:
  ```kotlin
  entry<PhotoDetailKey>(metadata = ListDetailSceneStrategy.detailPane()) { key ->
      PhotoDetailScreen(
          onNavigateBack = navigator.backOrNull(),
          viewModel = hiltViewModel<PhotoDetailViewModel, PhotoDetailViewModel.Factory>(creationCallback = { it.create(key) }),
      )
  }
  ```
- **Contribute** them with the generated `XEntryModule` (`@Provides @IntoSet fun provideXEntries(): EntryProviderInstaller = { navigator -> xEntries(navigator) }`).
- **Navigating to another feature**: add `implementation(project(":feature:<other>:api"))` to this impl and set
  `pendingNavigation = OtherKey(id)` (or call `navigator.navigate(OtherKey(id))` from the entry for a pure tap).
- `onNavigateBack = navigator.backOrNull()` — `null` on the root entry, so the start destination shows no Back
  control. System and predictive back go through `NavDisplay`'s `onBack`; intercept back only with
  `NavigationBackHandler` (the `navigation-event` skill), never the legacy `BackHandler`.
- **Becoming the start destination**: the app's `rememberNavBackStack(HomeKey)` takes this feature's key (`:app`
  depends on the impl, which `api`-exposes its keys); delete `Home.kt` and its entry.

## Adaptive layouts (phones, foldables, tablets, desktop)

- **List-detail**: mark entries `ListDetailSceneStrategy.listPane()` / `detailPane()` (`extraPane()`); `:app`'s
  `NavDisplay` already uses `rememberListDetailSceneStrategy()`. Never `ListDetailPaneScaffold`.
- **Within a screen**, branch on the window, not the device: `currentWindowAdaptiveInfo().windowSizeClass`
  (`isWidthAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND)`), adaptive grids
  (`LazyVerticalGrid(GridCells.Adaptive(minSize = …))`), max content widths on wide windows.
- Never lock orientation or resizability; support keyboard/mouse (focus, hover, right-click) where the screen
  is interactive — required on Googlebook/desktop. The `adaptive` skill covers MediaQuery, Grid/FlexBox and
  input-device handling in depth.
- Screenshot every screen on a phone **and** a tablet (below).

## Strings and errors

- Every user-facing string, `contentDescription` included, comes from the module's
  `src/main/res/values/strings.xml`, keys prefixed with its `resourcePrefix` (`gallery_…`). The shared Back label
  is `CoreUiR.string.core_ui_navigate_back` (`import <base>.core.ui.R as CoreUiR`).
- **Errors**: `:core:ui`'s `DomainError.toMessage()` words the built-in cases once; never re-word them. The screen
  words the area's typed errors it reacts to, from its own table, and falls back to `toMessage()`:
  ```kotlin
  @Composable
  private fun DomainError.message(): String = when (this) {
      PhotoError.TitleBlank -> stringResource(R.string.gallery_title_blank)
      is PhotoError.AlbumFull -> stringResource(R.string.gallery_album_full, limit)
      else -> toMessage()
  }
  ```
  Never show a `cause`.
- Plurals: `pluralStringResource(R.plurals.gallery_photo_count, count, count)`. Inside an effect, resolve with
  `LocalResources.current.getString(id)` captured outside the effect.
- Remove the template's `<feature>_placeholder_content` string and its `// TODO(android-forge):` line once real
  content exists (`android-reviewer` flags it).

## Composables, accessibility, RTL

- Sizes and gaps from `AppSpacing` / `AppDimens`; colors from `MaterialTheme.colorScheme`; text from
  `MaterialTheme.typography`. No `.sp` literals, no color literals outside `:core:designsystem`.
- `Icon` / `Image` / `AsyncImage` always pass `contentDescription` (a string resource, or an explicit `null` when decorative).
- Touch targets ≥ 48dp (`Modifier.minimumInteractiveComponentSize()` on custom clickables).
- RTL: `padding(start = …, end = …)`, `Alignment.Start` / `End` — never `left` / `right` / `absoluteOffset`.
- `Modifier.testTag("<screen>:<element>")` on every element a test or a QA journey must find.
- Every composable that emits UI takes `modifier: Modifier = Modifier` as its first optional parameter
  (compose-rules).

## Tests

`feature/<name>/impl/src/test/`:

- **ViewModel** — every intent's transitions, the on-create work, the error branch, the clearing of each slot.
  Real use cases over fakes from `:core:testing`:
  ```kotlin
  @Test
  fun creatingTheViewModelShowsThePhotos() = runTest {
      val photo = photo(id = "1", title = "a")
      val repository = FakePhotoRepository().apply { seed(photo) }
      val viewModel = GalleryViewModel(ObservePhotosUseCase(repository), RefreshPhotosUseCase(repository))

      viewModel.testWithInternalState(this, GalleryState.Initial) {
          runOnCreate()
          expectInternalState { copy(photos = listOf(photo)) }
          expectInternalState { copy(loading = true) }
          expectInternalState { copy(loading = false) }
          cancelAndIgnoreRemainingItems()       // the observation never completes
      }
  }
  ```
- **Screen** — Robolectric + `androidx.compose.ui.test.junit4.v2.createComposeRule()`: behavior on `XContent`
  through `testTag`s; the stateful `XScreen` with a ViewModel built **outside** `setContent` (Lint's
  `ViewModelConstructorInComposable`).
- **Screenshots** — Roborazzi, `@GraphicsMode(NATIVE)`, one test per device qualifier
  (`RobolectricDeviceQualifiers.Pixel7`, `.MediumTablet`; add foldable/desktop when the layout branches there);
  `./gradlew recordRoborazziDebug` after an intended change, review the PNGs, commit them.
- Tag tests covering an OpenSpec scenario `// Scenario: <exact name>`; `android-qa` traces through the tag.
- The generated `XViewModelTest` targets the template's no-arg ViewModel; rewrite it once the ViewModel takes use
  cases (it stops compiling — the cue).

## Before you hand it on

- The impl exposes nothing public; keys are in `:api`; no `:core:data` import; no other feature's `impl`.
- No `postSideEffect`, no `try/catch` in an intent, no `Dispatchers.*`, no repository or Navigator in a ViewModel;
  work starts in the on-create block.
- `State` has no defaults; every `pendingX` slot has its `LaunchedEffect` and `onXConsumed()`.
- Strings are prefixed and in `values/strings.xml`; the placeholder is gone; the accessibility checklist holds.
- Phone + tablet goldens recorded and reviewed.
- `./gradlew :feature:<name>:impl:testDebugUnitTest` while iterating; before pushing `./gradlew spotlessApply`, then
  `./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true`. User-visible change → ask
  for the `android-qa` agent.
