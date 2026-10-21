# The repository: where exceptions become `DomainError`

Use when implementing a repository — the `catchNetwork` / `catchStorage` boundaries, an offline-first repository, its mappers and its `DataModule` binding.

Both boundaries already ship — call them, don't re-implement them:

- `:core:network`'s `suspend fun <T> catchNetwork(block: suspend () -> T): Result<T, DomainError>` —
  `CancellationException` and any `Error` (OOM, stack overflow) rethrown first; an HTTP 404 → `NotFound`; any other
  `HttpException` → `Network.Http(status, code = null)`; `IOException` → `Network.Connectivity` (offline, DNS,
  timeouts); anything else → `Unknown(message)` (e.g. a body that doesn't parse). Logged with `Timber.w`.
- `:core:data`'s `catchStorage { }` — the same shape for Room, DataStore and file I/O: `CancellationException` and
  `Error`s rethrown first, everything else → `Unknown(message)`.

An offline-first repository — Room is the single source of truth, the network refreshes it:

```kotlin
package <base>.core.data.photo

internal class OfflineFirstPhotoRepository
    @Inject
    constructor(
        private val photoDao: PhotoDao,
        private val remote: PhotoRemoteDataSource,
    ) : PhotoRepository {
        override fun observePhotos(): Flow<List<Photo>> = photoDao.observeAll().map { rows -> rows.map { it.toModel() } }

        override suspend fun photo(id: PhotoId): Result<Photo, DomainError> =
            catchStorage { photoDao.byId(id.value) }.toErrorIfNull { DomainError.NotFound }.map { it.toModel() }

        override suspend fun setFavorite(id: PhotoId, favorite: Boolean): Result<Unit, DomainError> =
            catchStorage { photoDao.setFavorite(id.value, favorite) }

        override suspend fun refresh(): Result<Unit, DomainError> =
            catchNetwork { remote.photos() }.andThen { dtos -> catchStorage { photoDao.upsertAll(dtos.map { it.toEntity() }) } }
    }

// photo/PhotoMappers.kt
internal fun PhotoDto.toEntity() = PhotoEntity(id = id, title = title, description = description, favorite = favorite)

internal fun PhotoEntity.toModel() = Photo(id = PhotoId(id), title = title, description = description, favorite = favorite)
```

(Imports: `catchStorage` is `<base>.core.data.catchStorage`, `catchNetwork` is `<base>.core.network.catchNetwork`;
`Result`, `andThen`, `map`, `toErrorIfNull` from `com.github.michaelbull.result` next to `kotlinx.coroutines.flow.map`
— Kotlin picks the right `map` by receiver.) `:core:data` reaches the DAO and the remote data source through
`implementation(project(":core:database"))` / `(":core:network")` above its `// android-forge:core-data-deps` marker.

and its binding in `DataModule`: `@Binds fun bindsPhotoRepository(impl: OfflineFirstPhotoRepository): PhotoRepository`.

- **Every data-source call goes through a boundary helper.** Nothing a library throws reaches `:core:domain`.
  Meaningful answers become values at the boundary or right after it: a missing row is `null` → `NotFound`
  (`toErrorIfNull`, above), an HTTP 404 is `NotFound` from `catchNetwork`, an API error code → the area's typed
  error (`mapError`).
- It is **kotlin-result's** `runCatching` (`com.github.michaelbull.result.runCatching`), never the stdlib's, and
  `mapError` **rethrows `CancellationException` (and `Error`s) first, always**. Don't hand-roll
  `catch (e: Exception)` for the same job.
- A failure that is a *value* (a probe answering `null`) may use `try`/`catch` that rethrows
  `CancellationException` first, with a comment saying why every failure means the same thing there.
- Streams never throw: Room/DataStore flows, `.catch { }` where a source can fail.
- A `cause` is the exception message, for logs. The UI never shows it.
- Work that must outlive a screen (an upload, a sync) is WorkManager (`@HiltWorker`, opt-in) or an injected
  application-scope `CoroutineScope` — never a scope the repository creates and never cancels.
