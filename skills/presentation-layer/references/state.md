# State

Use when adding or changing a screen's `XState` — consumable slots, `Initial`, sealed page states.

```kotlin
internal data class GalleryState(
    val loading: Boolean,
    val photos: List<Photo>,
    val error: DomainError?,
    // Consumable slots: set by an intent, cleared by the paired onXConsumed() after the UI acts on them
    // (pendingNavigation → onNavigationConsumed(), pendingMessage → onMessageConsumed()).
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
