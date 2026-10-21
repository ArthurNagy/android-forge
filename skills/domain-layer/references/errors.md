# Errors: built-in cases, plus the area's typed errors

Use when a slice can fail — picking a built-in `DomainError` case or adding the area's `DomainError.Typed` errors.

`:core:domain` ships `<base>.core.domain.DomainError`. Its built-in cases cover what every app hits, and
`:core:ui`'s `toMessage()` words them once:

```kotlin
sealed interface DomainError {
    sealed interface Network : DomainError {
        data object Connectivity : Network                              // no connection, a drop, a timeout
        data class Http(val status: Int, val code: String?) : Network  // the server answered with an error
    }
    data object NotFound : DomainError
    data class Unknown(val cause: String?) : DomainError                // cause: diagnostic detail for logs
    interface Typed : DomainError                                       // extension point for an area's own errors
}
```

A domain area's **own** failures are a sealed interface in its package that extends `DomainError.Typed`, with
the payload a screen needs to react:

```kotlin
package <base>.core.domain.photo

import <base>.core.domain.DomainError

sealed interface PhotoError : DomainError.Typed {
    data object TitleBlank : PhotoError

    data class AlbumFull(
        val limit: Int,
    ) : PhotoError
}
```

- **Built-in cases for transport and generic failures** — the data layer produces them; don't re-type them per
  area (no `PhotoNetworkError`).
- **A typed error when a screen must react specifically** — say something only this area can explain, show a
  payload, offer a different action. Name it after what the user must hear.
- Screens word the typed errors they handle; anything else falls back to `toMessage()`'s generic message.
- A new **built-in** case is rare (e.g. `Unauthorized` once the app has accounts): `DomainError` is sealed, so
  it breaks `:core:ui`'s exhaustive `messageRes()` — the `@StringRes` behind `toMessage()`, which ViewModels also use
  for snackbar slots — until it has a string there.
- Every error is a value, never a `Throwable`; every error type extends `DomainError`.
