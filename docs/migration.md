# Migrating an existing project

The layer recipes `/android-forge-adopt` Phase B runs through the `android-migrator` agent — **one layer per
invocation**, in dependency order: `build` · `modules` · `dispatchers` · `result` · `repos` · `hilt` · `orbit` ·
`nav` · `visibility` · `tests` · `a11y` · `adaptive`, plus `foundations` (the base types `dispatchers` and `result`
need first). Each section names the doc that holds the rules, then **Detect** (find every site), **Transform** (edit
precisely) and **Verify** (residual grep empty + build). The migrator reads only its layer's section; the rules
themselves stay in the docs each section names — this page is the how.

Shell snippets run in the migrator's shell: they source its env file, which sets `PROJECT_ROOT`, `PLUGIN_ROOT` (the
android-forge plugin — `${CLAUDE_PLUGIN_ROOT}` in a command), `BASE_PACKAGE`, `BASE_PACKAGE_PATH`, `LAYER` and
`MIN_SDK`.

## foundations — the domain base types (before `dispatchers` / `result`)

The domain base types must exist. Render missing ones from the plugin templates (with `BASE_PACKAGE`):

```bash
source "${TMPDIR:-/tmp}/android-forge-migrate.env"; : "${PROJECT_ROOT:?}" "${PLUGIN_ROOT:?}" "${BASE_PACKAGE_PATH:?}"
AO="${PLUGIN_ROOT}/scripts/apply-overlay.sh"
for m in model domain testing; do
  [[ -d "${PROJECT_ROOT}/core/${m}" ]] || bash "${AO}" render-module "core.${m}" "${PLUGIN_ROOT}/overlay/modules/core/${m}" "${PROJECT_ROOT}/core/${m}" "${BASE_PACKAGE_PATH}"
done
bash "${AO}" patch-settings "${PROJECT_ROOT}" "core:model,core:domain,core:testing"
```

The templates also bring the theme-preference example (`ThemeMode`, `UserPreferencesRepository`, its use cases and
fake) — delete them if the app has its own settings model, keeping `DispatcherProvider`, `DomainError`, `UseCase`,
`TestDispatcherProvider`, `MainDispatcherRule` and `robolectric.properties`. `RealDispatcherProvider` + its `@Binds`
come with `:core:data` (`render-module core.data …`, then trim the same example). kotlin-result: Gradle coordinate
`com.michael-bull.kotlin-result:kotlin-result`, package `com.github.michaelbull.result`, `api` in `:core:domain`.

## build — conventions, AGP 9, KSP, catalog, toolchain
- Doc: `stack.md` § Toolchain, `ci.md`.
- **Detect:** AGP < 9 / Kotlin < 2.4 in the catalog; `org.jetbrains.kotlin.android` / `kotlin-kapt` plugins; modules
  configuring `compileSdk`, Lint, test options by hand; no `build-logic/`; a Gradle wrapper below 9.8.1; minSdk below 29.
- **Transform:** AGP 9 upgrade first through the **`agp-9-upgrade`** skill (built-in Kotlin, KAPT → KSP — Hilt and Room
  need KSP). Then copy `${PLUGIN_ROOT}/overlay/build-logic` into the project, `includeBuild("build-logic")` in `pluginManagement`,
  root `plugins { id("android-forge.root") }` (removing root `alias(...) apply false` lines for plugins build-logic
  provides), `patch-libs` with `${PLUGIN_ROOT}/overlay/gradle/libs.versions.toml.additions.tmpl` (`MIN_SDK` = the
  `min_sdk` the caller passed — `patch-libs` raises `androidMinSdk` to it, a floor), `pin-toolchain` (Gradle ≥ 9.8.1
  wrapper, 4 GiB daemon heap for Hilt/KSP + Robolectric), and
  replace each module's hand-written Android config with the matching convention
  (`android-forge.android.application` / `.android.library[.compose]` / `.jvm.library` + `.hilt` once Hilt is in).
  Keep module-specific config (namespace, `applicationId`, signing, flavors — but a flavored module fails the coverage
  gate's `coverageInputs` check, since android-forge measures one debug variant per module: move per-environment
  values to build types); drop hand-set `minSdk` — the conventions
  read `androidMinSdk`.
  ```bash
  source "${TMPDIR:-/tmp}/android-forge-migrate.env"; : "${PROJECT_ROOT:?}" "${PLUGIN_ROOT:?}" "${MIN_SDK:?}"
  mkdir -p "${PROJECT_ROOT}/build-logic" && cp -R "${PLUGIN_ROOT}/overlay/build-logic/." "${PROJECT_ROOT}/build-logic/"
  bash "${PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-libs "${PROJECT_ROOT}" "${PLUGIN_ROOT}/overlay/gradle/libs.versions.toml.additions.tmpl"
  bash "${PLUGIN_ROOT}/scripts/apply-overlay.sh" pin-toolchain "${PROJECT_ROOT}"
  ```
  minSdk: below 29 without a `min_sdk` from the caller → stop before editing and report `NEEDS INPUT` (raise to 29?);
  the conventions refuse anything below 26 (`java.time` without desugaring).
- **Verify:** `./gradlew assembleDebug lint` green; the gate tasks exist (`./gradlew help --task coverageVerify`);
  `gradle/wrapper/gradle-wrapper.properties` on ≥ 9.8.1.

## modules — the `:core:*` + `:feature:*:{api,impl}` shape (structural — per area)
- Doc: `architecture.md` § Module map, § Dependency direction; ADR 0003.
- **Detect:** entities, repositories, use cases, data sources, screens in `:app` or in feature-first modules; feature
  modules depending on data modules or on each other.
- **Transform:** move code into its module, one area at a time: entities → `:core:model`; repository interfaces + use
  cases → `:core:domain`; repository implementations → `:core:data` (internal); Retrofit/Room/DataStore code →
  `:core:network` / `:core:database` / `:core:datastore`; each user-facing area → `:feature:<name>:api` + `:impl`
  (render empty modules from `${PLUGIN_ROOT}/overlay/modules/feature/{api,impl}` and move the screens in). Room 2 stays Room 2 here —
  moving to Room 3 is a separate, opt-in change. Update package names and imports; build after each area.
- **Verify:** module dependencies follow the rules (features never reach `:core:data`); build.

## dispatchers — inject DispatcherProvider
- Doc: ADR 0006. **Detect:** `grep -rnE "Dispatchers\.(IO|Default|Main)" --include=*.kt "${PROJECT_ROOT}"` (exempt:
  `RealDispatcherProvider`, Room's `setQueryCoroutineContext`). **Transform:** constructor-inject `DispatcherProvider`
  into the use case / repository; `Dispatchers.IO → dispatchers.io`, etc. Drop `withContext(Dispatchers.IO)` around
  main-safe Room/Retrofit/DataStore suspend calls instead of converting it. ViewModels never take the provider — move
  the switching into a use case (TODO if unclear). **Verify:** residual grep empty; build.

## result — `Result<T, DomainError>`, no throws past the data layer
- Doc: ADR 0005, `data-layer` skill. **Detect:** use cases/repositories that throw or return nullable-for-error /
  sealed `Resource`/`UiResult` wrappers; `kotlin.Result`/stdlib `runCatching`; `try/catch` in ViewModels; error types
  outside `DomainError`. **Transform:** signatures → `Result<T, DomainError>` with explicit kotlin-result imports;
  data-source calls wrapped in `catchNetwork { }` / `catchStorage { }` (render `optional/network`'s `CatchNetwork.kt`
  into `:core:network`, `core/data`'s `CatchStorage.kt` into `:core:data` if missing); existing per-area error
  hierarchies become `sealed interface XError : DomainError.Typed`; ViewModels consume with `onOk`/`onErr`. Preserve
  existing exception→error mappings; TODO the unclear ones. **Verify:** no `throw` in domain paths, no `try/catch` in
  ViewModels, no stdlib `Result`; build + `testDebugUnitTest`.

## repos — one repository per domain type
- **Detect:** `AppRepository`/`DataRepository`, or a repository whose methods span types. **Transform:** split one god
  object per pass; move methods + implementations; update `@Binds` and call sites. **Verify:** build.

## hilt — Hilt with constructor injection
- Doc: ADR 0002, `stack.md` § Hilt. **Detect:** Koin (`module {`, `single {`, `koinViewModel`, `KoinComponent`),
  hand-rolled factories/singletons, Dagger components without Hilt, `ViewModelProvider.Factory` boilerplate, field
  injection outside framework classes.
- **Transform** (per module, leaves first): apply `android-forge.hilt`; `@HiltAndroidApp` on the `Application`,
  `@AndroidEntryPoint` on activities/services/receivers; `@Inject constructor` on use cases, repositories, data sources;
  `internal` Hilt modules with `@Binds` / `@Provides` beside what they bind (`DataModule`, `NetworkModule`, …);
  ViewModels → `@HiltViewModel` + `hiltViewModel()` (`@AssistedInject` for navigation arguments). Remove the old
  container module by module; both can coexist only while a module is mid-migration.
- **Verify:** no Koin/locator residue; `./gradlew assembleDebug` (Hilt validates the graph at build time); launch
  once on an emulator with `android run` — a missing binding fails the build, a wrong scope fails at launch.

## orbit — state-only Orbit ViewModels (per screen)
- Doc: `architecture.md` § ViewModel + Orbit; `presentation-layer` skill. **Detect:** `MutableStateFlow` UI state +
  `SharedFlow`/`Channel` events, `LiveData`, `SingleLiveEvent`, Orbit with a side-effect type, `postSideEffect`,
  `collectSideEffect`, loads in `LaunchedEffect(Unit)` / `init {}`.
- **Transform:** `@HiltViewModel internal class X @Inject constructor(...) : ViewModel(), OrbitContainerHost<XState, XState, Nothing>`
  with `orbitContainer(XState.Initial) { load() }`; each event becomes a consumable slot (`pendingX`) + `onXConsumed()`;
  the screen observes slots in `LaunchedEffect` (lambdas via `rememberUpdatedState`) and collects state with
  `collectAsState()`. LiveData → Orbit state directly. **Verify:** no events/`postSideEffect`; build + the screen's tests.

## nav — Navigation 3 with api/impl keys
- Doc: `architecture.md` § Navigation wiring; ADR 0004; the **`navigation-3`** skill (its migration guide covers Nav 2 →
  Nav 3). Fragment/XML screens must be Compose first — run the **`migrate-xml-views-to-jetpack-compose`** skill per
  screen (report each as its own step; that is a product-visible change, not a mechanical one).
- **Transform:** routes → `@Serializable` keys in each feature's `:api`; destinations → `entry<Key> { … }` in the
  feature's `xEntries(navigator)` contributed by an `@IntoSet` entry module; the app's `NavHost` → `:app`'s
  `AppNavigation` (render `${PLUGIN_ROOT}/overlay/app/src/main/kotlin/AppNavigation.kt.tmpl` and `:core:navigation` from
  the overlay); arguments → key properties + assisted injection; deep links per the `navigation-3` skill.
- **Verify:** no `NavHost`/`navController` left in migrated features; build; on an emulator, navigate, rotate,
  background-kill-relaunch (`android run`).

## visibility — restrictive visibility + explicit state (after `nav`)
- Doc: `architecture.md` § Visibility. **Detect:** public repository implementations/mappers/Hilt modules in data
  modules; public screens/ViewModels/state/entries in feature impls; default values on entities and `State`; `State`
  without `Initial`. **Transform:** `internal`; `companion object { val Initial }`; call sites pass every field
  (TODO where a removed default encoded behavior). Use-case constructors stay public. **Verify:** build.

## tests — fakes, Orbit harness, screen tests, goldens
- Doc: `testing.md`; the **`testing-setup`** skill for missing harness pieces. **Detect:** mocks of owned interfaces
  (MockK/Mockito), ViewModel tests asserting raw flows, screens without tests, no screenshot tests.
- **Transform:** fakes in `:core:testing`; Orbit `testWithInternalState`; Robolectric screen tests on the stateless
  `XContent` (v2 `createComposeRule`); phone + tablet Roborazzi tests, then `recordRoborazziDebug`. Raise coverage to
  the 85% gate area by area. **Verify:** `./gradlew coverageVerify -Proborazzi.test.verify=true`.

## a11y — accessibility, i18n, resource prefixes
- Doc: `i18n-a11y.md`. **Detect:** hard-coded strings; `Icon`/`Image` without `contentDescription`; `.sp` literals;
  `left/right`; resource keys without the module prefix. **Transform:** strings → the module's `strings.xml` with its
  `resourcePrefix` (set it in the build file; rename keys and their references); descriptions; typography; start/end.
  **Verify:** `./gradlew lint` (warnings are errors) + build.

## adaptive — large screens and edge-to-edge
- Doc: `form-factors/adaptive.md`; the **`adaptive`** and **`edge-to-edge`** skills. **Detect:** `screenOrientation`,
  `resizeableActivity="false"`, `setRequestedOrientation`, fixed widths, device-type checks, hard-coded bar heights,
  missing `enableEdgeToEdge()`. **Transform:** remove locks; window-size-class layouts; list-detail scene metadata on
  list/detail entries; insets via `Scaffold`/`WindowInsets`. **Verify:** build; screenshots on phone + tablet goldens;
  `android run` on a tablet/foldable AVD and look.
