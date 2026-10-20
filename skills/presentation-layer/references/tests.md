# Tests

Use when writing a feature's ViewModel, screen or Roborazzi screenshot tests.

`feature/<name>/impl/src/test/`:

- **ViewModel** — every intent's transitions, the on-create work, the error branch, the clearing of each slot.
  Real use cases over fakes from `:core:testing`:
  ```kotlin
  @Test
  fun creatingTheViewModelShowsThePhotos() = runTest {
      val photo = photo(id = "1", title = "a") // :core:testing's entity builder
      val repository = FakePhotoRepository().apply { seed(photo) }
      val viewModel =
          GalleryViewModel(ObservePhotosUseCase(repository), RefreshPhotosUseCase(repository), GetPhotoUseCase(repository))

      viewModel.testWithInternalState(this, GalleryState.Initial) {
          runOnCreate()
          expectInternalState { copy(photos = listOf(photo)) }
          expectInternalState { copy(loading = true) }
          expectInternalState { copy(loading = false) }
          cancelAndIgnoreRemainingItems() // the observation never completes
      }
  }
  ```
  An intent the test calls itself goes through `containerHost`:
  `containerHost.onPhotoClicked(PhotoId("1")); expectInternalState { copy(pendingNavigation = PhotoDetailKey(photoId = "1")) }`.
- **Screen** — Robolectric + `androidx.compose.ui.test.junit4.v2.createComposeRule()`: behavior on `XContent`
  through `testTag`s; the stateful `XScreen` with a ViewModel built **outside** `setContent` (Lint's
  `ViewModelConstructorInComposable`). Orbit runs intents off the main thread, so a stateful-screen test waits for
  the state instead of assuming it:
  `composeRule.waitUntil { composeRule.onAllNodesWithText("Sunset").fetchSemanticsNodes().isNotEmpty() }`.
- **Screenshots** — Roborazzi, `@GraphicsMode(NATIVE)`, one test per device qualifier
  (`RobolectricDeviceQualifiers.Pixel7`, `.MediumTablet`; add foldable/desktop when the layout branches there),
  plus one RTL golden per screen whose layout is directional (`@Config(qualifiers = "ar")`,
  [i18n-a11y.md](../../../docs/i18n-a11y.md) § Testing RTL); `./gradlew recordRoborazziDebug` after an intended
  change, review the PNGs, commit them.
- Tag tests covering an OpenSpec scenario `// Scenario: <exact name>`; `android-qa` traces through the tag.
- The generated tests target the template's no-arg ViewModel and its placeholder text. Once the ViewModel takes use
  cases, both stop compiling — the cue: rewrite `XViewModelTest` over fakes, and in `XScreenTest` rebuild
  `theScreenRendersTheViewModelState` (it constructs `XViewModel()` and looks for the placeholder string, which goes
  with the placeholder) around the real ViewModel and content, waiting for the state as above.
