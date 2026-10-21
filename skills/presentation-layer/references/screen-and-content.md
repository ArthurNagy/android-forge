# Screen and Content

Use when writing a stateful `XScreen` and its stateless `XContent` — one effect per slot, snackbars, which navigation path, insets.

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
        viewModel.onMessageConsumed()
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
  tests pass a ViewModel built outside composition) and `modifier: Modifier = Modifier`. An **assisted** ViewModel
  (key arguments) has no usable default — `hiltViewModel()` without its `creationCallback` fails at runtime — so
  its screen takes it as its first, required parameter
  (`PhotoDetailScreen(viewModel: PhotoDetailViewModel, onNavigateBack: (() -> Unit)?, modifier: Modifier = Modifier)`)
  and the entry builds it ([Navigation 3](navigation.md)).
- One `LaunchedEffect` per consumable slot; **lambda parameters used inside an effect go through
  `rememberUpdatedState`** (compose-rules `lambda-param-in-effect` fails the gate otherwise).
- `XContent` is `internal` and stateless (state + lambdas, no ViewModel, no Hilt) so screen and screenshot tests
  render it with any state:
  `GalleryContent(state: GalleryState, snackbarHostState: SnackbarHostState, onPhotoClick: (PhotoId) -> Unit, onRetry: () -> Unit, onNavigateBack: (() -> Unit)?, modifier: Modifier = Modifier)`.
  Host the `SnackbarHost` in its `Scaffold`, or `showSnackbar` never returns.
- **Which navigation path**: navigation that depends on an outcome (a save, a validation, a load) goes through
  `pendingNavigation`, set by the intent that knows the outcome. A tap that only navigates calls the screen's
  lambda directly (`onClick = { onNavigate(SettingsKey) }`) — no slot, no intent.
- Edge-to-edge is on (`enableEdgeToEdge()`): use `Scaffold`'s `innerPadding` / `WindowInsets` — never hard-code
  status-bar heights (the `edge-to-edge` skill).
