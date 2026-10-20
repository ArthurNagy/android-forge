# Fake and entity builder in `:core:testing`

Use when adding a fake of a `:core:domain` interface or a test entity builder in `:core:testing`.

Fakes of `:core:domain` interfaces **and** test entity builders go in
`core/testing/src/main/kotlin/<base-path>/core/testing/` (`<base-path>` = the base package with `/`) — the
domain's use-case tests **and** features' ViewModel tests both use them (every module's tests get `:core:testing`).

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
(`seed`, `nextError`). No MockK for interfaces you own. Next to it, one builder per entity, so tests name only the
fields they care about:

```kotlin
fun photo(id: String, title: String, description: String? = null, favorite: Boolean = false): Photo =
    Photo(id = PhotoId(id), title = title, description = description, favorite = favorite)
```

Test knobs and builders may have defaults; the no-defaults rule is for entities and `State`.
