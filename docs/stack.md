# Stack

Every locked library: why it was chosen, where it is used, and the idiom. Versions live in the
project's `gradle/libs.versions.toml` (seeded by `overlay/gradle/libs.versions.toml.additions.tmpl`,
refreshed by `/android-forge-bump-stack`). The rule for choosing: **the Android/Jetpack-first option
wherever one exists** — Google's docs, samples and Android skills then apply directly.

## Always included

### Jetpack Compose + Material 3 (adaptive)
- **Why**: Google's UI toolkit; Material 3 Adaptive (`NavigationSuiteScaffold`, `ListDetailSceneStrategy`,
  window size classes) makes one `:app` serve phones, tablets, foldables, desktops and XR panels.
- **Where**: every screen. Versions come from the Compose BOM (`androidxComposeBom`); never pin a single
  Compose artifact. `material3-adaptive` (`adaptive-navigation3`) is versioned separately.
- **Idiom**: `AppTheme(themeMode) { … }` from `:core:designsystem`; layouts that react to the window
  (`currentWindowAdaptiveInfo()` / the `adaptive` skill's MediaQuery guidance), never to device type.
- **Anti-patterns**: locking orientation or resizability (ignored on large screens since Android 16, no
  opt-out from Android 17 — see [form-factors/adaptive.md](form-factors/adaptive.md)); hard-coded `.dp`/`.sp`
  instead of tokens; `ListDetailPaneScaffold` (use Nav 3 scene strategies).

### Hilt (Dagger) on KSP
- **Why**: Google's recommended DI for Android; the Nav 3 modularization guide's `@IntoSet` entry
  builders, `hiltViewModel()`, `HiltWorker` and the testing skill all assume it. Compile-time graph:
  a missing binding fails the build, not the app. ADR 0002.
- **Where**: `@HiltAndroidApp MainApplication`; `@AndroidEntryPoint` on framework entry points only
  (activities, services, receivers); `@HiltViewModel` ViewModels; `@Module @InstallIn(SingletonComponent::class)`
  modules beside what they bind (`DataModule` in `:core:data`, `<Feature>EntryModule` in each impl).
- **Idiom**: constructor injection — `class X @Inject constructor(private val y: Y)`; `@Binds` an `internal`
  implementation to its public interface; route arguments through `@AssistedInject` +
  `hiltViewModel<VM, VM.Factory>(creationCallback = { it.create(key) })`; `@Multibinds` for a set that
  may be empty.
- **Anti-patterns**: field injection outside framework entry points; `EntryPointAccessors` as a service
  locator; `AndroidViewModel`; a Hilt module in `:core:domain` (JVM: it only uses `javax.inject`).

### Orbit MVI (state-only)
- **Why**: an explicit intent → reduce → state shape over Jetpack `ViewModel`, with a first-class test
  harness (`orbit-test`). Used state-only it matches Google's UI-layer rule ("don't send events from the
  ViewModel to the UI"). ADR 0001.
- **Where**: every ViewModel — `@HiltViewModel internal class FooViewModel @Inject constructor(...) : ViewModel(), OrbitContainerHost<FooState, FooState, Nothing>`
  with `override val container = orbitContainer<FooState, Nothing>(FooState.Initial) { load() }`.
- **Idiom**: `intent { reduce { state.copy(...) } }`; screens collect with `viewModel.collectAsState()`
  (`orbit-compose`); one-shot events are consumable state slots (`pendingX`) cleared by `onXConsumed()` intents.
- **Anti-patterns**: `postSideEffect` (the effect type is `Nothing`); mutating state outside `intent {}`;
  `LaunchedEffect(Unit) { viewModel.load() }` (load in the on-create block).

### Navigation 3 (androidx)
- **Why**: the official Compose navigation library: a user-owned back stack of `@Serializable` keys,
  scenes for adaptive multi-pane layouts, predictive back, and per-entry ViewModel stores. ADR 0004.
- **Artifacts**: `androidx.navigation3:navigation3-runtime` / `navigation3-ui` (`nav3Core`),
  `androidx.lifecycle:lifecycle-viewmodel-navigation3` (`rememberViewModelStoreNavEntryDecorator()`),
  `androidx.compose.material3.adaptive:adaptive-navigation3` (`ListDetailSceneStrategy`).
- **Idiom**: keys in `:feature:<name>:api`; entry builders contributed with Hilt `@IntoSet`; one
  `NavDisplay` in `:app` over `rememberNavBackStack(StartKey)` (saveable — survives process death)
  with `sceneStrategies = listOf(rememberListDetailSceneStrategy())`. See [architecture.md § Navigation wiring](architecture.md#navigation-wiring-nav-3-apiimpl-hilt-multibinding).
- **Anti-patterns**: string routes; a key without `@Serializable`; a feature importing another feature's
  `impl`; mutating the back stack from a ViewModel.

### kotlin-result (`Result<T, DomainError>`)
- **Why**: a two-parameter `Result<V, E>` makes each use case's failure modes part of its signature.
  Plain Kotlin — nothing KMP- or Android-specific — and lighter than Arrow. The stdlib `Result<T>` can
  only carry a `Throwable`. ADR 0005.
- **Coordinates**: `com.michael-bull.kotlin-result:kotlin-result` (+ `-coroutines` for `coroutineBinding`);
  import package `com.github.michaelbull.result` (explicit imports). `api` in `:core:domain`.
- **Idiom**: `onOk`/`onErr`/`fold`/`andThen`; the data boundary is kotlin-result's `runCatching { }.mapError { }`
  rethrowing `CancellationException` and any `Error` (`catchNetwork { }` in `:core:network`, `catchStorage { }` in
  `:core:data`).
- **Anti-patterns**: `kotlin.Result` / the **stdlib** `runCatching`; a `catch` that swallows
  `CancellationException`; `DomainError` extending `Throwable`; `.get()!!`.

### Kotlin coroutines + Flow
- **Why**: Google rates them "strongly recommended" for Android async work.
- **Idiom**: `suspend` one-shots, `Flow` streams (`observe…` / `…Stream` names). Code that switches dispatchers
  takes `DispatcherProvider` — a use case's CPU-heavy work on `default`, a data source's blocking call on `io`;
  Room, Retrofit and DataStore `suspend` APIs are main-safe, so nothing wraps them, and a ViewModel never takes it
  (ADR 0006). Only `RealDispatcherProvider` touches `Dispatchers.*` (and Room's `setQueryCoroutineContext` in
  `:core:database`'s `DatabaseModule`).

### kotlinx-serialization
- **Why**: Nav 3 keys are saved through it; Retrofit's converter and typed DataStore use it too.
- **Where**: every key, every DTO (`@Serializable data class PhotoDto(...)`).

### DataStore (Preferences)
- **Why**: Jetpack's coroutine/Flow key-value store; replaces SharedPreferences.
- **Where**: `:core:datastore` data sources (`UserPreferencesDataSource`), one `DataStore` instance per
  file, provided `@Singleton` by `DataStoreModule`. Typed data: a kotlinx-serialization JSON
  `Serializer<T>` (the Proto plugin needs AGP 9 opt-out flags). Secrets: a Tink-encrypted serializer —
  never `EncryptedSharedPreferences` (deprecated).
- **Idiom**: reads never throw — `retryWhen` on `IOException`: emit `emptyPreferences()`, then retry after a back-off
  (`catch` would complete the flow); the DataStore gets `ReplaceFileCorruptionHandler { emptyPreferences() }`
  (`DataStoreModule`). Writes may throw — the repository maps them to `DomainError`.

### Coil 3
- **Why**: the Compose-first image loader (Glide's Compose module is still beta); shares the app's
  `OkHttpClient` through `coil-network-okhttp`.
- **Where**: `AsyncImage(model = url, contentDescription = …)` where an image renders. Add
  `coil-compose` (+ `coil-network-okhttp`) to the module that first needs images; configure one
  `ImageLoader` (`SingletonImageLoader.Factory` on `MainApplication`, reusing the injected `OkHttpClient`).
- **Anti-patterns**: per-screen `ImageLoader`s; images without `contentDescription` (or `null` for
  decorative ones).

### Timber
- **Why**: the Android-idiomatic logger: a `DebugTree` in debug builds, a crash-reporter tree in
  release (Crashlytics/Sentry opt-in), nothing otherwise.
- **Idiom**: `Timber.w(e, "storing the theme mode failed")`; planted once in `MainApplication`.
- **Anti-patterns**: `android.util.Log`/`println` in app code; logging personal data.

### java.time + kotlin.time
- **Why**: native on every supported device — android-forge's minSdk floor is 29, and the build conventions
  fail at configuration below 26 (where `java.time` became part of the platform); `kotlin.time.Instant`/`Clock`
  for instants.
- **Anti-pattern**: `java.util.Date`/`Calendar`; `System.currentTimeMillis()` in testable code (inject a `Clock`).

### Android resources
- **Why**: native i18n — `res/values/strings.xml` per module, `stringResource(R.string.x)`,
  `pluralStringResource`, per-app language settings (`generateLocaleConfig = true` + `resources.properties`).
- **Where**: every user-facing string; each Android library module's keys carry its `resourcePrefix` (`:app` is
  exempt). See [i18n-a11y.md](i18n-a11y.md).

### Testing: JUnit 4 + Robolectric + Orbit test + Turbine + Compose UI Test v2 + Roborazzi
- JUnit 4 (Hilt and Compose test rules run on it) with `kotlin-test-junit` assertions; Robolectric runs
  Android code as local tests (SDK pinned to 36 by `:core:testing`'s `robolectric.properties`; the Android
  conventions run Android modules' tests on a JDK 21 launcher, JVM modules test on their JDK 17 toolchain); Orbit `testWithInternalState` + `runOnCreate()`; Turbine for Flows;
  `androidx.compose.ui.test.junit4.v2.createComposeRule`; Roborazzi screenshot goldens in
  `src/test/screenshots/`. Fakes over mocks. See [testing.md](testing.md).

### Quality gates
- **Android Lint** — `warningsAsErrors`, dependency-freshness checks off (bump-stack's job).
- **Slack's compose-lints** (`com.slack.lint.compose:compose-lint-checks`) — `lintChecks` on every Compose
  module, so `lint` also checks Compose usage (ADR 0007).
- **Spotless + ktlint + compose-rules** (`io.nlopez.compose.rules:ktlint`) — `spotlessCheck` in CI.
- **JaCoCo** (AGP `enableUnitTestCoverage`) aggregated at the root: `./gradlew coverageVerify` fails
  below 85% line coverage. Kover is avoided until its open AGP 9 / flaky-verify issues close (ADR 0008).
- **detekt is not used**: detekt < 2.0 forces AGP 9's built-in Kotlin off; revisit at detekt 2.0 stable (ADR 0007).

### Toolchain
AGP ≥ 9.4.1 with **built-in Kotlin** (no `org.jetbrains.kotlin.android` plugin) · Kotlin 2.4.x · KSP 2.3.x
(no kapt) · Gradle ≥ 9.8.1 · compileSdk/targetSdk 37 · minSdk 29 (default and floor; `/android-forge-init`
offers 29, 31 or 33) · Java 17 bytecode · a JDK 21 launcher for Android modules' local tests (JVM modules test on
JDK 17).
Every plugin comes from `build-logic` (precompiled convention plugins); modules apply them by id —
never `alias(libs.plugins.x)`.

## Opt-in libraries

### Network: Retrofit 3 + OkHttp 5 (`:core:network`)
- **Why**: the Android-native HTTP stack; one `OkHttpClient` shared with Coil.
- **Wiring** (`/android-forge-init` or later by hand from `overlay/optional/network`): Hilt `NetworkModule`
  (`Json { ignoreUnknownKeys = true }`, `OkHttpClient` + debug `HttpLoggingInterceptor`, `Retrofit` on
  `BuildConfig.API_BASE_URL` with the kotlinx-serialization converter), `catchNetwork { }`, the
  `INTERNET` permission. OkHttp is pinned to 5.x explicitly — Retrofit 3.0's POM still pulls 4.12.
- **Idiom**: a Retrofit service interface + a remote data source per type in `:core:network`; the
  repository in `:core:data` wraps each call in `catchNetwork { }`. Tests: `MockWebServer`
  (`mockwebserver3`) or a fake data source.

### Database: Room 3 (`:core:database`)
- **Why**: Jetpack's SQLite layer; Room 3 (`androidx.room3`) is KSP-only and coroutines-first.
- **Wiring**: the `android-forge.room` convention (KSP, `androidx.room3` plugin with exported schemas,
  bundled SQLite driver, framework driver + Robolectric for DAO tests). `:core:database` is created by the
  `data-layer` skill's **First table** recipe. Use Room 2.8 instead only if you need Paging/LiveData/Rx
  return types without Room 3's `@DaoReturnTypeConverters`.

### Background work: WorkManager (+ `hilt-work`)
Deferrable, guaranteed work (sync, uploads). A `:sync:work` module with `@HiltWorker` workers when the
first such job appears.

### Performance: Baseline Profiles + Macrobenchmark (`:benchmarks`)
`androidx.baselineprofile` on `:app` + a `com.android.test` module; regenerate with
`./gradlew :app:generateReleaseBaselineProfile` on a device and commit the profile.

### Crash reporting / performance monitoring
Play Vitals and Android Studio's App Quality Insights work with nothing added. Opt-in: **Firebase
Crashlytics + Performance** (Firebase BOM; `google-services` / `firebase-crashlytics` plugins) or
**Sentry Android** (`io.sentry:sentry-android` + its Gradle plugin). Either one plants a release `Timber.Tree`.
See [observability.md](observability.md).

### Distribution
GitHub Release artifacts by default; opt-in **Firebase App Distribution** for testers and
**gradle-play-publisher** (`com.github.triplet.play` ≥ 4.0 on AGP 9) for Play tracks — one track per form
factor (Wear, TV, AAOS each have their own). See [release.md](release.md).

### Security & identity (add with the feature that needs them)
**Credential Manager** (`androidx.credentials`) for passkeys/passwords/Sign in with Google · **Play Integrity**
standard requests on sensitive calls · **Tink** (`tink-android`) + Android Keystore for data at rest.

### Form-factor libraries
Car App Library, Compose for TV, Wear Compose Material 3, Jetpack XR, Glance, Media3 Cast — added by
`/android-forge-add-form-factor`; see [form-factors/](form-factors/).

## Excluded by default

- **Koin / Metro** — Hilt is the locked DI (ADR 0002).
- **Ktor / SQLDelight / Store5 / Kermit / kotlinx-datetime / Compose Multiplatform Resources** — the KMP
  choices of kmp-forge; android-forge uses the Android-native equivalents above.
- **MockK in shared test code** — fakes first; MockK only for framework or third-party types a fake can't stand in for.
- **Fastlane** — gradle-play-publisher covers Play uploads without Ruby.
- **detekt / Kover** — see Quality gates.

## Version policy

Manual refresh via `/android-forge-bump-stack` (no Dependabot/Renovate). It reads Google Maven, Maven
Central and — when Android Studio is running — `android studio version-lookup`, and proposes one catalog
diff the developer reviews for breaking changes before committing.
