# Navigation 3

Use when adding Nav 3 keys or entries, contributing them with `@IntoSet`, navigating to another feature, or changing the start destination.

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
- **Navigating to another feature**: add `implementation(project(":feature:<other>:api"))` to this impl, then use
  the same rule as [Screen and Content](screen-and-content.md)'s "Which navigation path" — `pendingNavigation = OtherKey(id)` when it depends on an outcome, the screen's
  `onNavigate(OtherKey(id))` lambda for a pure tap. The entry only wires `onNavigate = navigator::navigate`.
- `onNavigateBack = navigator.backOrNull()` — `null` on the root entry, so the start destination shows no Back
  control. System and predictive back go through `NavDisplay`'s `onBack`; intercept back only with
  `NavigationBackHandler` (the `navigation-event` skill), never the legacy `BackHandler`.
- **Becoming the start destination**: the app's `rememberNavBackStack(HomeKey)` takes this feature's key (`:app`
  depends on the impl, which `api`-exposes its keys); delete `Home.kt` and its entry.
