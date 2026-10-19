---
name: domain-layer
description: Write or change code in an android-forge project's :core:model / :core:domain modules — entities and value types without default values, use cases with @Inject constructors returning kotlin-result's Result<T, DomainError>, one repository interface per domain type, the sealed DomainError (built-in cases plus an area's own DomainError.Typed errors), DispatcherProvider, shared fakes in :core:testing, and use-case tests. Use in an android-forge project (its CLAUDE.md says "android-forge project rules") when adding or changing a use case, entity, repository interface or error case, when an OpenSpec task touches :core:domain or :core:model, or when deciding whether logic belongs in the domain layer.
---

# :core:model + :core:domain — android-forge style

The domain layer is the app's business logic in pure Kotlin, split in two **JVM modules**: `:core:model`
holds what the app knows (entities, value types); `:core:domain` holds what it can do (use cases), what it
needs from the outside (repository interfaces) and how that can fail (`DomainError`). Neither has Android,
Compose, Hilt, Room or Retrofit on its classpath, so all of it tests on the JVM in milliseconds. Canonical
rules: the plugin's [architecture.md](../../docs/architecture.md) (§ What goes where, § Visibility),
[testing.md](../../docs/testing.md) and the project's ADRs 0005 (Result + DomainError) and 0006
(DispatcherProvider). The gates — `android-reviewer`, Lint, JaCoCo — enforce them.

## What belongs here

| In the domain layer | Elsewhere |
|---|---|
| entities and value types (`Photo`, `PhotoId`) → `:core:model` | DTOs (`:core:network`), Room entities (`:core:database`) |
| use cases (`ObservePhotosUseCase`) → `:core:domain` | ViewModels, state, strings → `:feature:<name>:impl` |
| repository **interfaces** (`PhotoRepository`) → `:core:domain` | implementations → `:core:data` (internal) |
| `DomainError` (built-in cases) and each area's typed errors → `:core:domain` | their words → `:core:ui`'s `toMessage()` / the screen that reacts |
| `DispatcherProvider` (interface) → `:core:domain` | `Dispatchers.IO` / `Default` / `Main` (only `RealDispatcherProvider` in `:core:data`) |

Dependencies: Kotlin stdlib, kotlinx-coroutines (`api`), kotlin-result (`api`), kotlin-result-coroutines,
`javax.inject` (the `@Inject` annotation — Hilt builds use cases without the domain depending on Hilt),
`java.time` / `kotlin.time`. Never Android, Compose, Hilt modules, Room, Retrofit, DataStore, Coil or Timber.
Package by area: `<base>.core.domain.photo`, `<base>.core.model` (small) or `<base>.core.model.photo`.

## Adding a slice — in this order

Entity (`:core:model`) → the area's typed errors (if it has failures of its own) → repository interface →
use case → fake in `:core:testing` → tests. Each step compiles on its own; `:core:data` and feature work can
start once the interface exists.

### 1. Entities and value types (`:core:model`)

```kotlin
package <base>.core.model

@JvmInline
value class PhotoId(
    val value: String,
)

data class Photo(
    val id: PhotoId,
    val title: String,
    val description: String?,
    val favorite: Boolean,
)
```

- **No default values.** Every call site states every field, and adding a field breaks every place that must
  decide its value. (`null` is a value you pass explicitly, not a default.)
- Immutable: `val`s and read-only collections. An invariant the type must always hold goes in `init { require(…) }`.
- IDs as value classes, so a `PhotoId` can't be passed where a `UserId` is expected. Nav 3 keys carry the raw
  `String` (`PhotoDetailKey(photoId = id.value)`), not the entity.
- No presentation: no display strings, no formatting, no colors, no `@StringRes`. Time is `java.time` /
  `kotlin.time.Instant`.

### 2. Errors: built-in cases, plus the area's typed errors

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
  it breaks `:core:ui`'s exhaustive `messageRes()` until it has a string there.
- Every error is a value, never a `Throwable`; every error type extends `DomainError`.

### 3. Repository interfaces

```kotlin
package <base>.core.domain.photo

interface PhotoRepository {
    /** Every stored photo, as it changes. Never throws. */
    fun observePhotos(): Flow<List<Photo>>

    suspend fun photo(id: PhotoId): Result<Photo, DomainError>

    suspend fun setFavorite(id: PhotoId, favorite: Boolean): Result<Unit, DomainError>

    /** Fetches fresh photos into local storage; observers see them through [observePhotos]. */
    suspend fun refresh(): Result<Unit, DomainError>
}
```

- **One per domain type.** Never an `AppRepository`. Two types that are really one aggregate become one domain type.
- One-shot operations are `suspend` and return `Result<T, DomainError>`. Streams are `Flow` and **never throw**
  (`observe…` names). Offline-first: the stream comes from local storage; `refresh()` reports whether the
  network part worked.
- Domain types only in signatures: no DTOs, Room entities, `Response`, `Preferences`.
- Only the interface lives here; its `internal` implementation is in `:core:data` (the `data-layer` skill).

### 4. Use cases

```kotlin
package <base>.core.domain.photo

import <base>.core.domain.UseCase
import <base>.core.model.Photo
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

/** The photos to show, sorted by title. */
class ObservePhotosUseCase
    @Inject
    constructor(
        private val photos: PhotoRepository,
    ) : UseCase {
        operator fun invoke(): Flow<List<Photo>> = photos.observePhotos().map { list -> list.sortedBy { it.title.lowercase() } }
    }
```

- **Public class, public `@Inject` constructor.** Hilt builds it in production (no module needed); feature
  tests build it directly over a fake. Implement the `UseCase` marker.
- One `operator fun invoke`. ViewModels depend on use cases, never on repositories, so a pass-through gets one
  too. Write a use case when a screen needs the operation, not for every repository method in advance.
- Business rules live here: validation, ordering, combining repositories, choosing which error applies.
  Validate before calling the repository: `if (title.isBlank()) return Err(PhotoError.TitleBlank)`.
- CPU-heavy work takes `DispatcherProvider` and switches with `withContext(dispatchers.default)`; repositories
  move their own I/O. Never `Dispatchers.*` here.
- **Failures are values.** No `throw`, no `try/catch`, no `!!` / `getOrThrow()` / `unwrap()`. Not `kotlin.Result`
  or the stdlib's `runCatching`.
- Several steps: `coroutineBinding` stops at the first `Err`.

  ```kotlin
  import com.github.michaelbull.result.Result
  import com.github.michaelbull.result.coroutines.coroutineBinding

  class ToggleFavoriteUseCase
      @Inject
      constructor(
          private val photos: PhotoRepository,
      ) : UseCase {
          suspend operator fun invoke(id: PhotoId): Result<Photo, DomainError> = coroutineBinding {
              val photo = photos.photo(id).bind()
              photos.setFavorite(id, !photo.favorite).bind()
              photo.copy(favorite = !photo.favorite)
          }
      }
  ```
- kotlin-result members are imported one by one (`Result`, `Ok`, `Err`, `map`, `mapError`, `andThen`, …): ktlint
  rejects wildcard imports. Its Gradle coordinate (`com.michael-bull.kotlin-result`) differs from its package
  (`com.github.michaelbull.result`).

### 5. Wiring

Nothing to register: Hilt constructs `@Inject` use cases on demand. The repository interface is bound to its
implementation in `:core:data`'s `DataModule` (`@Binds`).

### 6. Fake in `:core:testing`

Fakes of `:core:domain` interfaces go in `core/testing/src/main/kotlin/<base>/core/testing/` — the domain's
use-case tests **and** features' ViewModel tests both use them (every module's tests get `:core:testing`).

```kotlin
package <base>.core.testing

class FakePhotoRepository : PhotoRepository {
    private val store = MutableStateFlow<Map<PhotoId, Photo>>(emptyMap())
    var nextError: DomainError? = null

    fun seed(vararg photos: Photo) = store.update { current -> current + photos.associateBy { it.id } }

    override fun observePhotos(): Flow<List<Photo>> = store.map { it.values.toList() }

    override suspend fun photo(id: PhotoId): Result<Photo, DomainError> =
        nextError?.let { Err(it) } ?: store.value[id]?.let { Ok(it) } ?: Err(DomainError.NotFound)

    override suspend fun setFavorite(id: PhotoId, favorite: Boolean): Result<Unit, DomainError> =
        photo(id).map { photo -> store.update { it + (id to photo.copy(favorite = favorite)) } }

    override suspend fun refresh(): Result<Unit, DomainError> = nextError?.let { Err(it) } ?: Ok(Unit)
}
```

A fake behaves like the real thing (in-memory state, a stream that reflects writes) and exposes knobs
(`seed`, `nextError`). Test knobs may have defaults; the no-defaults rule is for entities and `State`. No MockK
for interfaces you own.

### 7. Tests

`core/domain/src/test/kotlin/…`: JUnit 4 + `kotlin.test` assertions + Turbine. Every use case gets its happy
path and **each error it can return**. Tag a test that covers an OpenSpec scenario with
`// Scenario: <exact name>`, which is how QA traces coverage.

```kotlin
class ObservePhotosUseCaseTest {
    @Test
    fun emitsPhotosSortedByTitle() = runTest {
        val repository = FakePhotoRepository().apply { seed(photo(id = "1", title = "b"), photo(id = "2", title = "a")) }

        ObservePhotosUseCase(repository)().test {
            assertEquals(listOf("a", "b"), awaitItem().map { it.title })
        }
    }
}

class ToggleFavoriteUseCaseTest {
    @Test
    fun anUnknownPhotoIsNotFound() = runTest {
        assertEquals(Err(DomainError.NotFound), ToggleFavoriteUseCase(FakePhotoRepository())(PhotoId("missing")))
    }
}
```

A use case that takes `DispatcherProvider` gets `TestDispatcherProvider(testScheduler)` — the `runTest`
scheduler; a dispatcher with its own scheduler hangs or fails with "Detected use of different schedulers".
Build test entities with a small local builder (`photo(id, title)`) that passes every field explicitly.

## Before you hand it on

- `:core:model` / `:core:domain` import nothing outside the allowed list; nothing references `Dispatchers.*`.
- Entities have no default values. Use cases are public with public `@Inject` constructors.
- Transport and generic failures use the built-in `DomainError` cases; the area's own failures are its sealed
  `DomainError.Typed` errors, each one a screen will react to.
- Each new use case has tests for success and every error it can return; each fake matches its interface.
- `./gradlew :core:domain:test` while iterating. Before pushing: `./gradlew spotlessApply`, then the CI gate
  `./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true` (75% line coverage).
