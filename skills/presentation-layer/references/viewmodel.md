# ViewModel

Use when writing a `@HiltViewModel` Orbit ViewModel — on-create work, intents, consumable slots, key arguments via `@AssistedInject`.

```kotlin
@HiltViewModel
internal class GalleryViewModel
    @Inject
    constructor(
        private val observePhotos: ObservePhotosUseCase,
        private val refreshPhotos: RefreshPhotosUseCase,
        private val getPhoto: GetPhotoUseCase,
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

        // Outcome-dependent navigation: the list may be stale, so open the photo only if it still exists.
        fun onPhotoClicked(id: PhotoId) =
            intent {
                getPhoto(id)
                    .onOk { reduce { state.copy(pendingNavigation = PhotoDetailKey(photoId = id.value)) } }
                    .onErr { error -> reduce { state.copy(pendingMessage = error.messageRes()) } }
            }

        fun onNavigationConsumed() = intent { reduce { state.copy(pendingNavigation = null) } }

        fun onMessageConsumed() = intent { reduce { state.copy(pendingMessage = null) } }
    }
```

- `@HiltViewModel` + `@Inject constructor` + `ViewModel()` + `OrbitContainerHost<S, S, Nothing>` +
  `orbitContainer<S, Nothing>(S.Initial) { … }` (Orbit 12). No base class, no `AndroidViewModel`, no `Context`.
- **Start work in the on-create block** — loads and long-lived observations. A `LaunchedEffect(Unit) { viewModel.load() }`
  would reload every time the user comes back.
- **State-only events.** No `postSideEffect`; a one-shot event is a `pendingX` slot + `fun onXConsumed()` — the
  slot's name without `pending` (`pendingMessage` → `onMessageConsumed()`).
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
