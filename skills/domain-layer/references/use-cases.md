# Use cases

Use when writing a use case — business rules, validation, combining repositories, multi-step `coroutineBinding`, kotlin-result imports.

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
