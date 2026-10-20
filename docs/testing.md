# Testing

## Layout

```
core/domain/src/test/            use case tests (pure JVM)
core/data/src/test/              repository tests over fakes of their DAOs and data sources
core/datastore/src/test/         DataStore data sources (a real store on a temp file)
core/database/src/test/          DAO tests (Robolectric + in-memory Room on the framework SQLite driver)
core/network/src/test/           catchNetwork + remote data sources (MockWebServer)
core/ui/src/test/                shared composables (Robolectric + Compose UI Test)
feature/<name>/impl/src/test/    ViewModel tests (Orbit) + screen tests (Compose UI Test) + screenshots (Roborazzi)
feature/<name>/impl/src/test/screenshots/   committed Roborazzi goldens
app/src/test/                    app-level ViewModel + navigation tests
app/src/androidTest/             instrumented tests (on demand — not in the PR gate)
core/testing/src/main/           shared doubles: fakes of :core:domain interfaces, TestDispatcherProvider,
                                 MainDispatcherRule, robolectric.properties (SDK pin), ScreenshotTolerancePlugin
benchmarks/                      Macrobenchmark + Baseline Profile generator (opt-in, device only)
```

Every Android module's local tests get `:core:testing` from the convention plugin (that is also how the
Robolectric SDK pin reaches them); a JVM module adds `testImplementation(project(":core:testing"))` itself, as
`:core:domain` does. Module-local fakes stay in that module's `src/test`.

## Frameworks

- **JUnit 4** with `kotlin.test` assertions (`kotlin-test-junit`). JUnit 4 because Hilt, Compose and
  Robolectric test rules run on it.
- **Robolectric** — Android framework code as fast local tests. `:core:testing`'s `robolectric.properties`
  pins `sdk=36` (Robolectric's newest runtime) while the app targets 37; the Android conventions run Android
  modules' local tests on a **JDK 21** launcher and export `jdk.internal.access` (Robolectric's SDK 35+ runtimes
  need both). JVM modules (`:core:model`, `:core:domain`, `:feature:*:api`) test on their JDK 17 toolchain.
- **Orbit test** — `testWithInternalState(this, State.Initial) { runOnCreate(); expectInternalState { … } }`.
- **Turbine** — `flow.test { awaitItem() … }` for Flows (use cases, repositories, DataStore).
- **Compose UI Test (v2 APIs)** — `androidx.compose.ui.test.junit4.v2.createComposeRule()` under
  Robolectric (`@RunWith(AndroidJUnit4::class)`); the v1 rule is deprecated.
- **Roborazzi** — screenshot goldens: `composeRule.onRoot().captureRoboImage()` with
  `@GraphicsMode(GraphicsMode.Mode.NATIVE)` and a device qualifier (`RobolectricDeviceQualifiers.Pixel7`,
  `.MediumTablet`, …). Goldens live in `src/test/screenshots/` and are committed.
  - `./gradlew recordRoborazziDebug` — (re)record after an intended UI change; review the PNGs.
  - CI verifies: `-Proborazzi.test.verify=true` makes every local test run compare; a missing golden fails.
    Up to 0.1% of an image's pixels may differ (`:core:testing`'s `ScreenshotTolerancePlugin` sets it for every
    module), so macOS-recorded goldens survive Linux CI's anti-aliasing; anything bigger needs a re-record
    ([ci.md](ci.md) § Screenshot goldens across OSes).
- **UI Automator 2.4 / instrumented tests** — `app/src/androidTest` for flows that need a real device;
  run on demand or in an opt-in Gradle Managed Device job (see [ci.md](ci.md)).

## Fakes-first policy

Write hand-rolled `Fake<Name>` implementations of every interface you own; shared ones go in `:core:testing`,
next to an entity builder per type (`photo(id = "1", title = "a")`, with defaults for the fields a test doesn't
care about). The gallery slice's fake, in `:core:testing` (full file: the `domain-layer` skill's fakes reference):

```kotlin
/** In-memory [PhotoRepository]: [seed] stores photos, [nextError] makes the next call fail once. */
class FakePhotoRepository : PhotoRepository {
    private val store = MutableStateFlow<Map<PhotoId, Photo>>(emptyMap())

    var nextError: DomainError? = null

    fun seed(vararg photos: Photo) = store.update { current -> current + photos.associateBy { it.id } }

    override fun observePhotos(): Flow<List<Photo>> = store.map { it.values.toList() }

    override suspend fun photo(id: PhotoId): Result<Photo, DomainError> =
        takeError()?.let { Err(it) } ?: store.value[id]?.let { Ok(it) } ?: Err(DomainError.NotFound)

    override suspend fun setFavorite(
        id: PhotoId,
        favorite: Boolean,
    ): Result<Unit, DomainError> = photo(id).map { photo -> store.update { it + (id to photo.copy(favorite = favorite)) } }

    override suspend fun refresh(): Result<Unit, DomainError> = takeError()?.let { Err(it) } ?: Ok(Unit)

    private fun takeError(): DomainError? = nextError.also { nextError = null }
}
```

`Result`/`Ok`/`Err` are kotlin-result (`com.github.michaelbull.result`), not `kotlin.Result`.

### When MockK is allowed
Only for framework or third-party types you don't own and can't reasonably fake (a vendor SDK client).
Never mock an interface you authored or a domain type. Comment why above the mock:
`// mocked: vendor SDK client has no seam`. HTTP needs no mock (`MockWebServer`); storage needs no
mock (temp-file DataStore, in-memory Room).

## ViewModel test pattern

```kotlin
class GalleryViewModelTest {
    @Test
    fun aFailedRefreshShowsTheError() = runTest {
        val repository = FakePhotoRepository().apply { nextError = DomainError.Network.Connectivity }
        val viewModel =
            GalleryViewModel(ObservePhotosUseCase(repository), RefreshPhotosUseCase(repository), GetPhotoUseCase(repository))

        // Orbit 12: the initial state is asserted automatically; runOnCreate() runs the container's
        // on-create block; then every emitted state, in order. The empty photo list changes nothing.
        viewModel.testWithInternalState(this, GalleryState.Initial) {
            runOnCreate()
            expectInternalState { copy(loading = true) }
            expectInternalState { copy(loading = false, error = DomainError.Network.Connectivity) }
            cancelAndIgnoreRemainingItems() // the photo observation never completes
        }
    }
}
```

Real use cases over the shared fake — never a mock of the use case. An intent the test calls itself goes through
`containerHost` (`containerHost.onPhotoClicked(PhotoId("1"))`, then `expectInternalState { … }`).

A ViewModel with a key argument (assisted injection) is constructed directly in tests:
`PhotoDetailViewModel(PhotoDetailKey("p1"), GetPhotoUseCase(repository))`.

## DispatcherProvider in tests

Use `:core:testing`'s `TestDispatcherProvider(testScheduler)` — always with the `runTest` scheduler, so
delays run on one virtual clock (a `StandardTestDispatcher()` with its own scheduler fails with
"Detected use of different schedulers" or hangs). Code on `viewModelScope` outside Orbit's harness needs
`@get:Rule val mainDispatcherRule = MainDispatcherRule()`.

## Screen tests (Compose UI Test + Roborazzi)

```kotlin
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class GalleryScreenTest {
    @get:Rule
    val composeRule = createComposeRule() // androidx.compose.ui.test.junit4.v2

    private val samplePhoto = photo(id = "1", title = "Sunset") // :core:testing's entity builder
    private val withPhoto = GalleryState.Initial.copy(photos = listOf(samplePhoto))

    @Test
    fun tappingAPhotoOpensIt() {
        var opened: PhotoId? = null
        composeRule.setContent {
            AppTheme { GalleryContent(withPhoto, SnackbarHostState(), onPhotoClick = { opened = it }, onRetry = {}, onNavigateBack = null) }
        }

        composeRule.onNodeWithTag("gallery:photo:${samplePhoto.id.value}").performClick()

        assertEquals(samplePhoto.id, opened)
    }

    @Test
    @Config(qualifiers = RobolectricDeviceQualifiers.MediumTablet)
    fun tablet() {
        composeRule.setContent { AppTheme { GalleryContent(withPhoto, SnackbarHostState(), onPhotoClick = {}, onRetry = {}, onNavigateBack = null) } }
        composeRule.onRoot().captureRoboImage()
    }
}
```

- Test the stateless `…Content` with explicit state; test the stateful `…Screen` by passing a ViewModel built
  **outside** composition (`val vm = GalleryViewModel(…); setContent { GalleryScreen(…, viewModel = vm) }` —
  Lint's `ViewModelConstructorInComposable` rejects constructing it inside). Orbit processes intents on its own
  background event loop, so wait for the state rather than assume it:
  `composeRule.waitUntil { composeRule.onAllNodesWithText("Sunset").fetchSemanticsNodes().isNotEmpty() }`.
- Screenshot every screen on a phone **and** a tablet (adaptive is the default) — add foldable/desktop
  qualifiers when the layout branches there.
- `testTag` on tap targets, named `<screen>:<element>` (`gallery:retry`; a list item adds its ID:
  `gallery:photo:<id>`); content descriptions double as accessibility checks.

## Coverage

`./gradlew coverageVerify` aggregates JaCoCo data from every module's local tests (Robolectric-run
Compose code counts; `:core:testing` and `com.android.test` modules are not measured) and fails below **85% line
coverage**; `./gradlew coverageReport` writes `build/reports/jacoco/coverageReport/html/`. Excluded as generated
or wiring-only: Compose singletons, serializers, Hilt modules (`*Module`) and Hilt/Dagger-generated classes,
`R`/`BuildConfig`, `MainApplication`/`MainActivity`, feature `api` modules and `*EntriesKt`, `DomainError`, design
tokens, `RealDispatcherProvider`. The list is `coverageExcludes` in build-logic's `android-forge.root` convention
(ADR 0008).

## Running on a device or emulator

Local tests run on the JVM; checking the app itself goes through Google's **Android CLI** (`android`):

```bash
android emulator list                          # AVDs
android emulator start <avd>                   # returns once booted
./gradlew :app:assembleDebug
android describe --project_dir=.               # where each module's APK is (QA uses this, not hard-coded paths)
android run --apks=app/build/outputs/apk/debug/app-debug.apk --device=emulator-5554
android layout --flat --device=emulator-5554   # UI as JSON (text, content-desc, bounds, center)
android input --device=emulator-5554 tap "text=Gallery"            # selector-based input
android input --device=emulator-5554 key back                      # back, home, recents, DPAD_*, …
android screen capture --device=emulator-5554 -o screen.png
android emulator stop <avd>
```

- **Android CLI, not adb.** Install, launch, inspection and input all go through `android`. adb is used
  only to list attached devices (`adb devices -l`).
- **Emulator first.** Agents never install on a **physical** device without the user's explicit OK —
  except the `android-qa` agent under its rules (below). With more than one device, always pass `--device`.
- **Other form factors** (Wear, TV, Automotive, XR, glasses, foldable) need AVDs the CLI's `emulator create`
  can't make — `scripts/avd.sh ensure <form-factor>` creates them (asks first). Android Auto runs in the
  Desktop Head Unit. See [android-cli.md](android-cli.md).
- Worth a run after DI or navigation changes: launch, rotate, background the app and kill its process,
  relaunch — that exercises Hilt start-up, Nav 3 back-stack saving (`@Serializable` keys) and resource packaging.

## Acceptance: scenarios → tagged tests → QA

With OpenSpec, a change's acceptance criteria are its spec **scenarios** (`#### Scenario: <name>`). Each one
gets a test that names it — a `// Scenario: <exact scenario name>` comment on the test (rule in
`openspec/config.yaml`; the spec critic checks `tasks.md` plans it):

```kotlin
// Scenario: Picked theme survives a restart
@Test
fun pickedThemeIsRestored() = runTest { … }
```

The **`android-qa` agent** maps every scenario of a change to its tagged test, flags missing or hollow ones,
and — in device mode — runs each **user-visible** scenario as an Android CLI journey on every form factor the
change touches (phone; tablet/foldable when layout changed; the watch for `:wear`; the TV for `:tv`; …),
screenshots at every check, a crash or ANR fails the journey; it writes `build/qa/<change>/report.md` and
returns PASS / FAIL / ERROR — ERROR rather than PASS when it could not verify something. It never edits code.

- **Supervised:** after `/opsx:apply`, ask for the `android-qa` agent ("QA the `<change>` change").
- **Autonomous loop:** the third code-gate reviewer — `qa: device | tests-only | off` (+ `qa-device: auto | <serial> | <AVD>`)
  in `openspec/AUTOLOOP.md`.

## What to test

- **Always**: every OpenSpec scenario — a test tagged `// Scenario: <name>`.
- **Always**: every use case (happy path + each `DomainError` branch) and repository boundary.
- **Always**: every ViewModel intent's state transitions.
- **Always**: every screen — behavior through Compose UI Test, layout through phone + tablet goldens.
- **Often**: mappers with real transformation; DAO queries; `catchNetwork` call sites.
- **On demand**: instrumented flows (`androidTest`), Macrobenchmark startup runs before a release.
