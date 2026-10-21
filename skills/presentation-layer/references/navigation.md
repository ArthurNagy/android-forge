# Navigation 3

Use when adding Nav 3 keys or entries, contributing them with `@IntoSet`, navigating to another feature, or changing the start destination.

- **Keys** live in the feature's `:api`, are `@Serializable`, and carry IDs (the back stack is saved).
- **Entries** (`XEntries.kt`, internal): one `entry<Key> { … }` per screen; the screen gets lambdas, never the Navigator:
  ```kotlin
  @OptIn(ExperimentalMaterial3AdaptiveApi::class) // the material3-adaptive scene metadata is still experimental
  internal fun EntryProviderScope<NavKey>.galleryEntries(navigator: Navigator) {
      entry<GalleryKey>(metadata = ListDetailSceneStrategy.listPane()) { key ->
          GalleryScreen(onNavigate = navigator::navigate, onNavigateBack = navigator.backOrNull(key))
      }
  }
  ```
  A key argument reaches the ViewModel through its factory:
  ```kotlin
  entry<PhotoDetailKey>(metadata = ListDetailSceneStrategy.detailPane()) { key ->
      PhotoDetailScreen(
          viewModel = hiltViewModel<PhotoDetailViewModel, PhotoDetailViewModel.Factory>(creationCallback = { it.create(key) }),
          onNavigateBack = navigator.backOrNull(key),
      )
  }
  ```
- **Contribute** them with the generated `XEntryModule` (`@Provides @IntoSet fun provideXEntries(): EntryProviderInstaller = { navigator -> xEntries(navigator) }`).
- **Navigating to another feature**: add `implementation(project(":feature:<other>:api"))` to this impl, then use
  the same rule as [Screen and Content](screen-and-content.md)'s "Which navigation path" — `pendingNavigation = OtherKey(id)` when it depends on an outcome, the screen's
  `onNavigate(OtherKey(id))` lambda for a pure tap. The entry only wires `onNavigate = navigator::navigate`.
- `onNavigateBack = navigator.backOrNull(key)` — pass the key the entry lambda receives; `null` when that key is the
  root (bottom) entry of the back stack, so the start destination — and a list pane shown beside its detail — has no
  Back control. System and predictive back go through `NavDisplay`'s `onBack`; intercept back only with
  `NavigationBackHandler` (the `navigation-event` skill), never the legacy `BackHandler`.
- **Becoming the start destination**: the app's `rememberNavBackStack(HomeKey)` takes this feature's key (`:app`
  depends on the impl, which `api`-exposes its keys); delete `Home.kt` and its entry.
