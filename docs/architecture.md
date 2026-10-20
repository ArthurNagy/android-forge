# Architecture

`android-forge` projects follow Google's reference app architecture: a **UI layer**, a **domain layer**
and a **data layer** ([Guide to app architecture](https://developer.android.com/topic/architecture)),
split into modules the way the [modularization guide](https://developer.android.com/topic/modularization/patterns)
and the [Navigation 3 modularization guide](https://developer.android.com/guide/navigation/navigation-3/modularize)
describe — app modules, `:core:*` modules, and features as an `api` + `impl` pair — with one rule
stricter than Google's: **a feature reaches data only through `:core:domain`** (ADR 0003).

## Module map

```
:app                     the phone/tablet/foldable/desktop app (+ XR/glasses/Auto pieces when opted in):
                         MainApplication (@HiltAndroidApp), MainActivity (@AndroidEntryPoint), AppNavigation
                         (the one Nav 3 back stack), the start destination. Assembles the DI graph.
:core:model              pure-Kotlin entities and value IDs (JVM module)
:core:domain             use cases, repository INTERFACES, DomainError, DispatcherProvider (JVM module)
:core:data               repository IMPLEMENTATIONS + their Hilt bindings, RealDispatcherProvider
:core:datastore          DataStore data sources (preferences)
:core:database           Room 3 database, entities, DAOs        (created with the first table)
:core:network            Retrofit/OkHttp, remote data sources, catchNetwork { } boundary   (opt-in)
:core:designsystem       AppTheme, color schemes, AppType/AppSpacing/AppDimens, shared stateless components
:core:ui                 composables shared by features, DomainError.toMessage(), shared strings
:core:navigation         Navigator, EntryProviderInstaller, NavigationModule (@Multibinds), shared scene strategies
:core:testing            shared test doubles (fakes, TestDispatcherProvider, MainDispatcherRule) + the
                         Robolectric SDK pin and screenshot tolerance — a test-only dependency (the Android
                         conventions add it)
:feature:<name>:api      the feature's Nav 3 keys — nothing else (JVM module)
:feature:<name>:impl     the feature's screens, Orbit ViewModels, state, strings, and the Hilt
                         @IntoSet entry builder that contributes its entries to the app
:wear · :tv · :automotive   one app module per extra device type (opt-in; same applicationId, own Play track)
:car                     Car App Library screens + CarAppService shared by :app (Auto) and :automotive (opt-in)
:glasses · :widget       libraries the :app links in for XR glasses / home-screen widgets (opt-in)
:benchmarks              Macrobenchmark + Baseline Profile generator for :app (opt-in, com.android.test)
build-logic/             precompiled convention plugins (android-forge.*)
```

## Dependency direction

```
:app / :wear / :tv / :automotive ──▶ :feature:*:impl ──▶ :feature:<other>:api
         │                                 ├──▶ :core:domain ──▶ :core:model
         │                                 ├──▶ :core:ui ──▶ :core:domain
         │                                 ├──▶ :core:designsystem ──▶ :core:model
         │                                 └──▶ :core:navigation
         └──▶ :core:data ──▶ :core:domain   (implements its repository interfaces)
                   ├──▶ :core:datastore
                   ├──▶ :core:database
                   └──▶ :core:network ──▶ :core:domain   (DomainError for catchNetwork)
:core:testing ──▶ :core:domain               (test-only; every Android module's tests get it)
```

Rules (the `android-reviewer` agent enforces them):
- `:core:model` and `:core:domain` are **JVM modules** — no Android, Compose, Hilt, Retrofit or Room.
  `:core:domain` may use `javax.inject.Inject` (Hilt builds use cases) and kotlin-result.
- **A feature impl depends on `:core:domain` (use cases + interfaces), `:core:model`, `:core:ui`,
  `:core:designsystem`, `:core:navigation` and other features' `:api` — never on `:core:data`,
  `:core:datastore`, `:core:database`, `:core:network`, or another feature's `:impl`.** Repositories
  reach a feature only as `:core:domain` interfaces that Hilt binds in `:core:data`.
- Only app modules depend on `:core:data`: they assemble the graph.
- `:core:testing` is never an `implementation` dependency. The Android conventions add it to every Android
  module's tests; a JVM module that needs it declares `testImplementation(project(":core:testing"))` (`:core:domain`
  does).
- A form-factor app (`:wear`, `:tv`, `:automotive`) reuses `:core:model`/`:core:domain`/`:core:data`
  but not the phone UI (`:core:designsystem`, `:core:ui`, phone features): its toolkit differs (Wear
  Compose, Compose for TV, Car App Library). See [form-factors/](form-factors/).

## What goes where

Step-by-step recipes for each layer's code — with the tests the gates expect — are the plugin's
`domain-layer`, `data-layer` and `presentation-layer` skills; they load in an android-forge project.
This document stays the source of truth for the rules.

### `:core:domain`
- Use cases: `class ObserveThemeModeUseCase @Inject constructor(private val repository: UserPreferencesRepository) : UseCase { operator fun invoke(): Flow<ThemeMode> }` — public class, public `@Inject` constructor (Hilt builds it; feature tests build it with a fake from `:core:testing`).
- Repository **interfaces** (`UserPreferencesRepository`), one per domain type.
- `DomainError` — a `sealed interface` with the built-in cases every app hits (`Network.Connectivity`,
  `Network.Http(status, code)`, `NotFound`, `Unknown(cause)`), worded once by `:core:ui`'s exhaustive
  `DomainError.toMessage()`, plus the extension point `DomainError.Typed` that a domain area's own
  sealed errors extend (with the payload a screen needs to react).
- `DispatcherProvider` — the only way production code reaches a dispatcher. Code that switches dispatchers takes it:
  a use case doing CPU-heavy work (`withContext(dispatchers.default)`), a data source calling a blocking API
  (`dispatchers.io`). Room, Retrofit and DataStore are main-safe, so repositories don't wrap them; ViewModels never
  take it.

`Result<T, DomainError>` is [kotlin-result](https://github.com/michaelbull/kotlin-result)'s two-param
`Result<V, E>` — Gradle coordinate `com.michael-bull.kotlin-result:kotlin-result`, import package
`com.github.michaelbull.result` (import members explicitly; ktlint rejects wildcards; 2.x deprecates
`onSuccess`/`onFailure` — use `onOk`/`onErr`). Declared `api` in `:core:domain` so it flows to every
consumer. **Not** `kotlin.Result` (single-param, `Throwable`-only). ADR 0005.

### `:core:model`
Entities and value types shared by domain, data and UI: `data class Photo(val id: PhotoId, val title: String)`,
`@JvmInline value class PhotoId(val value: String)`, enums like `ThemeMode`. **No default values** —
construct explicitly, so every call site states its intent and a new field surfaces everywhere.
It is its own module so the low-level modules (`:core:designsystem`, `:core:datastore`, `:core:database`) can use the
types without seeing use cases or repository interfaces (ADR 0003).

### `:core:data` (+ `:core:datastore`, `:core:database`, `:core:network`)
- Repository **implementations** — `internal class OfflineFirstPhotoRepository @Inject constructor(...)` —
  bound to the `:core:domain` interface in the module's `internal interface DataModule { @Binds … }`.
- Data sources live in the module of their technology: DataStore sources in `:core:datastore`, DAOs in
  `:core:database`, Retrofit services + remote data sources in `:core:network`. They are public only
  because `:core:data` uses them; nothing else may depend on those modules.
- DTOs (`PhotoDto`, `@Serializable`) and entities (`PhotoEntity`, Room) map to `:core:model` types in
  the repository (`PhotoDto.toModel()`). DTOs may keep wire-format defaults.
- **The exception boundary.** Data sources may throw; repositories never do. Network calls run through
  `catchNetwork { … }` (`:core:network`: kotlin-result `runCatching` + `mapError`; `CancellationException` and any
  `Error` rethrown; `IOException` → `Network.Connectivity`; Retrofit `HttpException` → `NotFound` for a 404, else
  `Network.Http(status, code = null)`; anything else → `Unknown`); storage calls run through `catchStorage { … }`
  (`:core:data`, same shape, every other failure → `Unknown`).
- **One repository per domain type** — never an `AppRepository` god object. Its name says where the truth lives:
  `OfflineFirst<Type>Repository` (local storage is the source of truth, the network refreshes it),
  `Offline<Type>Repository` (local only, like `OfflineUserPreferencesRepository`), `Remote<Type>Repository` (no
  local copy).
- **Offline-first** = Room as the single source of truth: the repository exposes the DAO's `Flow`,
  refreshes from the network into Room, and (with the WorkManager opt-in) syncs in the background.

### `:core:designsystem` and `:core:ui`
- `:core:designsystem`: `AppTheme(themeMode, dynamicColor) { }`, `LightScheme`/`DarkScheme`, `AppType`,
  `AppSpacing`, `AppDimens`, and shared **stateless** components (buttons, cards) — hoisted state only.
- `:core:ui`: composables that several features share and that know domain types —
  `DomainError.toMessage()` / `messageRes()`, the shared `core_ui_navigate_back` label, empty/error
  states.

### `:core:navigation`
- `Navigator` — `navigate(key)`, `goBack()`, `canGoBack`, `backOrNull(key)`, over the app's saveable back stack.
- `typealias EntryProviderInstaller = EntryProviderScope<NavKey>.(Navigator) -> Unit` — what each
  feature contributes.
- `NavigationModule` — `@Multibinds` declares the (possibly empty) `Set<EntryProviderInstaller>`.

### `:feature:<name>:api`
Only `@Serializable` Nav 3 keys: `data object GalleryKey : NavKey`, `data class PhotoDetailKey(val photoId: String) : NavKey`.
Keys carry IDs, never objects (the destination loads what it needs from the data layer).

### `:feature:<name>:impl`
- `GalleryScreen.kt` — `internal` stateful entry (`viewModel: GalleryViewModel = hiltViewModel()` default
  parameter, observes consumable slots with `LaunchedEffect`) + `internal GalleryContent` (stateless;
  screenshot and UI tests render it with any state).
- `GalleryViewModel.kt` — `@HiltViewModel internal class GalleryViewModel @Inject constructor(...) : ViewModel(), OrbitContainerHost<GalleryState, GalleryState, Nothing>`.
- `GalleryState.kt` — `internal data class` with **no defaults** and `companion object { val Initial }`.
- `GalleryEntries.kt` — `internal fun EntryProviderScope<NavKey>.galleryEntries(navigator: Navigator)` with one `entry<Key> { Screen(...) }` per screen.
- `GalleryEntryModule.kt` — `@Module @InstallIn(SingletonComponent::class) internal object` with
  `@Provides @IntoSet fun provideGalleryEntries(): EntryProviderInstaller = { navigator -> galleryEntries(navigator) }`.
- `res/values/strings.xml` — keys carry the module's `resourcePrefix` (`gallery_…`; Lint enforces it).
- Tests: `GalleryViewModelTest` (Orbit `testWithInternalState`), `GalleryScreenTest` (Robolectric +
  Compose UI Test v2 + Roborazzi phone/tablet goldens).
- Feature-owned analytics live in the feature (`GalleryAnalytics.kt` over an injected client).

### `:app`
Rendered by `/android-forge-init` from `overlay/app/`: `MainApplication` (`@HiltAndroidApp`; Timber's
`DebugTree` in debug), `MainActivity` (`@AndroidEntryPoint`, `enableEdgeToEdge()`, injects
`Set<@JvmSuppressWildcards EntryProviderInstaller>`, renders `AppTheme(themeMode)` from
`MainActivityViewModel`), `AppNavigation` (below), and `Home.kt` — a placeholder start destination until a
feature owns the launch screen. A feature joins the app by **one line**: `implementation(project(":feature:<name>:impl"))`
above the `// android-forge:feature-modules` marker. Field injection appears only here and in other
framework entry points (services, receivers).

## Visibility

Declare everything **`private`**, widen to **`internal`** when another file of the module needs it, and
use **`public`** only for a module's intentional cross-module API. A public declaration with no consumer
outside its module is a leak — tighten it.

| Module | Public (cross-module API) | `internal` / `private` |
|---|---|---|
| `:core:domain` | use cases (+ public `@Inject` ctor), repository interfaces, `DomainError`, `DispatcherProvider` | helpers |
| `:core:model` | entities, value types | — |
| `:core:data` | nothing but what Hilt needs | repository implementations, `DataModule`, `RealDispatcherProvider`, mappers |
| `:core:datastore` / `:core:database` / `:core:network` | data sources, DAOs, DTOs, `catchNetwork` (used by `:core:data`) | Hilt modules, factories |
| `:feature:*:api` | keys | — |
| `:feature:*:impl` | nothing (Hilt reaches the `internal` entry module) | `Screen`, `Content`, `ViewModel`, `State`, entries, entry module |

Companion rules:
- **No default values on domain entities or presentation `State`.** `State` carries its starting value in
  `companion object { val Initial = … }` (one source of truth for `orbitContainer(...)` and tests).
- **Use-case constructors stay public** — a feature test builds a real use case over a fake repository.

## ViewModel + Orbit pattern (state-only)

```kotlin
internal data class GalleryState(
    val loading: Boolean,
    val photos: List<Photo>,
    val error: DomainError?,
    // Consumable event slots — set inside intent {}, cleared by the paired onXConsumed()
    // (pendingNavigation → onNavigationConsumed(), pendingMessage → onMessageConsumed()).
    val pendingNavigation: NavKey?,
    @StringRes val pendingMessage: Int?, // which message; the screen resolves the text
) {
    companion object {
        val Initial = GalleryState(loading = false, photos = emptyList(), error = null, pendingNavigation = null, pendingMessage = null)
    }
}

@HiltViewModel
internal class GalleryViewModel @Inject constructor(
    private val observePhotos: ObservePhotosUseCase,
    private val refreshPhotos: RefreshPhotosUseCase,
    private val getPhoto: GetPhotoUseCase,
) : ViewModel(), OrbitContainerHost<GalleryState, GalleryState, Nothing> {
    override val container = orbitContainer<GalleryState, Nothing>(GalleryState.Initial) {
        observe() // once per ViewModel = once per back-stack entry
        refresh()
    }

    private fun observe() = intent {
        observePhotos().collect { photos -> reduce { state.copy(photos = photos) } }
    }

    fun refresh() = intent {
        reduce { state.copy(loading = true, error = null) }
        refreshPhotos()
            .onOk { reduce { state.copy(loading = false) } }
            .onErr { error -> reduce { state.copy(loading = false, error = error) } }
    }

    // Outcome-dependent navigation goes through the slot; a tap that only navigates calls the screen's lambda.
    fun onPhotoClicked(id: PhotoId) = intent {
        getPhoto(id)
            .onOk { reduce { state.copy(pendingNavigation = PhotoDetailKey(photoId = id.value)) } }
            .onErr { error -> reduce { state.copy(pendingMessage = error.messageRes()) } }
    }

    fun onNavigationConsumed() = intent { reduce { state.copy(pendingNavigation = null) } }

    fun onMessageConsumed() = intent { reduce { state.copy(pendingMessage = null) } }
}

// GalleryScreen(onNavigate: (NavKey) -> Unit, onNavigateBack: (() -> Unit)?, modifier, viewModel = hiltViewModel())
// gets plain lambdas from its entry builder, never the Navigator, and renders the stateless
// GalleryContent(state, snackbarHostState, onPhotoClick = viewModel::onPhotoClicked, onRetry = viewModel::refresh, onNavigateBack).
// rememberUpdatedState: the effect outlives recompositions (compose-rules' lambda-param-in-effect).
val currentOnNavigate by rememberUpdatedState(onNavigate)
LaunchedEffect(state.pendingNavigation) {
    val key = state.pendingNavigation ?: return@LaunchedEffect
    currentOnNavigate(key)
    viewModel.onNavigationConsumed()
}
```

The full, compiling gallery slice — entity, use cases, fake, repository, ViewModel, screen and tests — is in the
`domain-layer`, `data-layer` and `presentation-layer` skills.

Rules:
- **No `postSideEffect`.** The side-effect type is `Nothing`. One-shot events are consumable state slots
  (`pendingNavigation: NavKey?`, `@StringRes pendingMessage: Int?` — never resolved text), observed with
  `LaunchedEffect`, consumed, then cleared by the paired `onXConsumed()` intent — the slot's name without
  `pending`. Google's UI-layer guidance says
  the same: handle events in the ViewModel and expose them as state.
- Loading and long-lived observation start in the container's on-create block
  (`orbitContainer(Initial) { load() }`) — once per ViewModel, i.e. once per back-stack entry — never in a
  `LaunchedEffect(Unit)`. Tests run it with `runOnCreate()`.
- **Navigation**: when it depends on an outcome (a save, a validation, a lookup), the intent sets
  `pendingNavigation`; a tap that only navigates calls the screen's `onNavigate(Key)` lambda directly. Entries
  only wire `onNavigate = navigator::navigate`.
- No dispatchers in ViewModels — no `DispatcherProvider` in the constructor, no `withContext`: Orbit runs intents
  off the main thread, and code that switches dispatchers (a use case's CPU-heavy work, a data source's blocking
  call) takes `DispatcherProvider` itself (ADR 0006).
- No `AndroidViewModel`, no `Context` in a ViewModel.
- **Route arguments** come from the key through assisted injection:
  ```kotlin
  @HiltViewModel(assistedFactory = PhotoDetailViewModel.Factory::class)
  internal class PhotoDetailViewModel @AssistedInject constructor(
      @Assisted private val key: PhotoDetailKey,
      private val getPhoto: GetPhotoUseCase,
  ) : ViewModel(), OrbitContainerHost<PhotoDetailState, PhotoDetailState, Nothing> {
      @AssistedFactory interface Factory { fun create(key: PhotoDetailKey): PhotoDetailViewModel }
      …
  }
  // in the entry builder — the screen takes the assisted ViewModel as a required parameter:
  entry<PhotoDetailKey> { key ->
      PhotoDetailScreen(
          viewModel = hiltViewModel<PhotoDetailViewModel, PhotoDetailViewModel.Factory>(creationCallback = { it.create(key) }),
          onNavigateBack = navigator.backOrNull(key),
      )
  }
  ```

### Sub-states via sealed interface

When page-level states are mutually exclusive (`Loading | Loaded | Error`), promote to a sealed interface;
its initial state is an explicit object (`orbitContainer(GalleryState.Loading)`). Default to the flat data
class; promote when booleans start fighting each other.

## Navigation wiring (Nav 3, api/impl, Hilt multibinding)

```kotlin
// :feature:gallery:impl — contributes its entries; navigates with other features' api keys
@OptIn(ExperimentalMaterial3AdaptiveApi::class) // the material3-adaptive scene metadata is still experimental
internal fun EntryProviderScope<NavKey>.galleryEntries(navigator: Navigator) {
    entry<GalleryKey>(metadata = ListDetailSceneStrategy.listPane()) { key ->
        GalleryScreen(onNavigate = navigator::navigate, onNavigateBack = navigator.backOrNull(key))
    }
}

@Module @InstallIn(SingletonComponent::class)
internal object GalleryEntryModule {
    @Provides @IntoSet
    fun provideGalleryEntries(): EntryProviderInstaller = { navigator -> galleryEntries(navigator) }
}

// :app — AppNavigation.kt (rendered by init), inside @OptIn(ExperimentalMaterial3AdaptiveApi::class) @Composable
// fun AppNavigation(entryProviderInstallers, modifier); never lists features
val backStack = rememberNavBackStack(HomeKey)          // saveable: survives rotation and process death
val navigator = remember(backStack) { Navigator(backStack) }
NavDisplay<NavKey>(
    backStack = backStack,
    onBack = navigator::goBack,
    entryDecorators = listOf(rememberSaveableStateHolderNavEntryDecorator(), rememberViewModelStoreNavEntryDecorator()),
    sceneStrategies = listOf(rememberListDetailSceneStrategy()),   // adaptive list-detail on wide windows
    entryProvider = entryProvider {
        entry<HomeKey> { HomeScreen() }
        entryProviderInstallers.forEach { install -> install(navigator) }
    },
)
```

- Every key is `@Serializable` (the back stack is saved through kotlinx-serialization).
- A feature navigates to another by depending on its `:api` and calling `navigator.navigate(OtherKey(id))`
  from its entry builder; the ViewModel only sets `pendingNavigation`.
- `onNavigateBack` is `navigator.backOrNull(key)`, with the key the entry lambda receives — `null` when that key
  is the root (bottom) entry of the back stack, so the start destination, and a list pane shown beside its detail,
  has no Back control. System/predictive back goes through `NavDisplay`'s `onBack`.
- Multi-pane: mark entries with `ListDetailSceneStrategy.listPane()` / `detailPane()` metadata; never use
  `ListDetailPaneScaffold` directly (the `adaptive` skill).
- Top-level destinations (bottom bar / rail): `NavigationSuiteScaffold` in `:app` around `NavDisplay`, with
  one back stack per top-level destination when the product needs them (the `navigation-3` skill's
  multiple-back-stacks recipe).

## When to add modules

- **Per-domain data modules** (`:core:data` splits into `:core:data-photos`, …) once `:core:data` holds
  several unrelated areas or builds slowly.
- **`:core:analytics`**, **`:core:notifications`**, **`:sync:work`** (WorkManager opt-in) when a second
  consumer appears.
- **A screen used by two features** moves to `:core:ui` (stateless) — features still never depend on
  each other's `impl`.

New modules apply a convention plugin (`android-forge.jvm.library` when no Android API is needed —
Google: prefer Kotlin modules — else `android-forge.android.library[.compose]`) and get an `include(...)`
in `settings.gradle.kts`. They follow the same dependency rules.

## Rationale

- **Google's shape, so Google's guidance applies directly**: the modularization guide's module types, the
  Nav 3 guide's `api`/`impl` split with Hilt `@IntoSet` entry builders, and Now in Android's `:core:*`
  naming — Android skills, docs and samples all assume it.
- **Stricter feature boundary than Google** (features see `:core:domain`, not `:core:data`): every feature
  has the same shape, ViewModels test against fakes of domain interfaces, and the reviewer has one rule
  instead of a judgment call per repository.
- **`api`/`impl` instead of app-wired callbacks**: features navigate to each other without the app knowing
  every edge, and the app module never changes when a feature adds a destination.
