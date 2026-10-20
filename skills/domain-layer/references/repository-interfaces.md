# Repository interfaces

Use when declaring or extending a repository interface in `:core:domain`.

```kotlin
package <base>.core.domain.photo

interface PhotoRepository {
    /** Every stored photo, as it changes. Never throws. */
    fun observePhotos(): Flow<List<Photo>>

    suspend fun photo(id: PhotoId): Result<Photo, DomainError>

    suspend fun setFavorite(
        id: PhotoId,
        favorite: Boolean,
    ): Result<Unit, DomainError>

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
