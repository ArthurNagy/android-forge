---
name: data-layer
description: Write or change code in an android-forge project's data layer — :core:data (internal repository implementations bound with Hilt @Binds to :core:domain interfaces, mappers, the catchStorage boundary), :core:network (Retrofit services, remote data sources, DTOs, the catchNetwork boundary), :core:database (Room 3 entities, DAOs, AppDatabase, the First table recipe) and :core:datastore (DataStore preferences), offline-first repositories with Room as the source of truth, and their tests (fakes, MockWebServer, Robolectric DAO tests, temp-file DataStore). Use in an android-forge project (its CLAUDE.md says "android-forge project rules") when implementing a repository, adding an API call, a stored preference, a table or a cache, or when an OpenSpec task touches a :core data module.
---

# Data layer — android-forge style

The data layer implements the repository interfaces `:core:domain` declares. It is the only code that talks to
the network, the disk or platform storage, and the only place exceptions may exist: **data sources may throw,
repositories never do — every failure leaves as a `DomainError`.** Canonical rules: the plugin's
[architecture.md](../../docs/architecture.md) (§ `:core:data`, § Visibility), [stack.md](../../docs/stack.md)
(Retrofit, Room 3, DataStore) and [testing.md](../../docs/testing.md). The domain side of a slice (entity,
`DomainError` cases, the interface) comes first — see the `domain-layer` skill.

## Shape

`<base-path>` is the base package with `/`:

```
core/data/src/main/kotlin/<base-path>/core/data/
  DataModule.kt                 internal interface — @Binds every repository (+ DispatcherProvider)
  CatchStorage.kt               the storage boundary: exceptions → DomainError.Unknown (with tests)
  RealDispatcherProvider.kt     the only Dispatchers.* in the app, besides Room's setQueryCoroutineContext
  photo/
    OfflineFirstPhotoRepository.kt   internal class … : PhotoRepository
    PhotoMappers.kt             internal PhotoDto.toEntity(), PhotoEntity.toModel()
core/network/src/main/kotlin/<base-path>/core/network/     (opt-in; "First API call" below)
  NetworkModule.kt              OkHttpClient, Json, Retrofit (+ @Provides for each service)
  CatchNetwork.kt               the network boundary: IOException / HttpException / other → DomainError
  photo/
    PhotoApi.kt                 internal Retrofit service interface
    PhotoDto.kt                 @Serializable wire shape (public: the data source returns it)
    PhotoRemoteDataSource.kt    public interface + internal Retrofit implementation (@Binds in a module)
core/database/src/main/kotlin/<base-path>/core/database/   (created by "First table" below)
  AppDatabase.kt · DatabaseModule.kt · photo/PhotoEntity.kt · photo/PhotoDao.kt
core/datastore/src/main/kotlin/<base-path>/core/datastore/
  UserPreferencesDataSource.kt · DataStoreModule.kt
```

- **`:core:data` exposes nothing but what Hilt needs**: repository implementations, mappers and the Hilt module
  are `internal`. The rest of the app sees the `:core:domain` interface.
- The storage/network modules expose their data sources, DTOs, entities and DAOs **only because `:core:data`
  uses them** — nothing else may depend on them (the reviewer checks). Their implementations and Hilt modules
  stay `internal`.
- **One repository per domain type**, and at most one data source per domain type **per technology** (one remote
  data source, one DAO, one preferences source) — an offline-first repository combines its DAO and its remote
  data source.
- **Repository names say where the truth lives**: `OfflineFirst<Type>Repository` when local storage is the source
  of truth and the network refreshes it; `Offline<Type>Repository` when the data is local only (the template's
  `OfflineUserPreferencesRepository`); `Remote<Type>Repository` when nothing is stored locally.

## Recipe: implement a repository

### 1. Remote data source (`:core:network`)

**First API call** — when `:core:network` doesn't exist yet (the network opt-in wasn't picked at init), create it
once; the Retrofit/OkHttp catalog entries are already there:

```bash
AO="${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh"
BASE_PACKAGE="<base package>" bash "${AO}" render-module core.network "${CLAUDE_PLUGIN_ROOT}/overlay/optional/network" core/network "<base-path>"
bash "${AO}" patch-settings . "core:network"
```

Then `implementation(project(":core:network"))` in `core/data/build.gradle.kts` above the
`// android-forge:core-data-deps` marker, `<uses-permission android:name="android.permission.INTERNET" />` above
`<application` in `app/src/main/AndroidManifest.xml`, and the real base URL in `core/network/build.gradle.kts`
(`API_BASE_URL`). The module ships `NetworkModule` (one `OkHttpClient`, `Json`, `Retrofit`) and `catchNetwork` with
its tests.

```kotlin
@Serializable
data class PhotoDto(
    val id: String,
    val title: String,
    val description: String? = null,                  // the API omits it when empty
    @SerialName("is_favorite") val favorite: Boolean = false,
)

internal interface PhotoApi {
    @GET("photos")
    suspend fun photos(): List<PhotoDto>
}

/** May throw: IOException (transport), HttpException (non-2xx), SerializationException (bad body). */
interface PhotoRemoteDataSource {
    suspend fun photos(): List<PhotoDto>
}

internal class RetrofitPhotoRemoteDataSource
    @Inject
    constructor(
        private val api: PhotoApi,
    ) : PhotoRemoteDataSource {
        override suspend fun photos(): List<PhotoDto> = api.photos()
    }

@Module
@InstallIn(SingletonComponent::class)
internal interface PhotoNetworkModule {
    @Binds
    fun bindsPhotoRemoteDataSource(impl: RetrofitPhotoRemoteDataSource): PhotoRemoteDataSource

    companion object {
        @Provides
        fun providePhotoApi(retrofit: Retrofit): PhotoApi = retrofit.create(PhotoApi::class.java)
    }
}
```

- A DTO mirrors the wire format; it is the one **model type** that may have default values (for fields the API
  omits).
- A Retrofit `suspend` function returning a body **throws `HttpException` on non-2xx**. When a status means
  something (404 = "doesn't exist"), declare `Response<PhotoDto>` and decide in the data source:
  `if (response.code() == 404) return null`, else `response.body() ?: throw HttpException(response)`.
- One `Retrofit` / `OkHttpClient` for the app (`NetworkModule`); per-host clients get a Hilt qualifier.
  Auth headers go in an OkHttp `Interceptor`; secrets come from `BuildConfig` fields fed by
  `local.properties`/CI env, never source ([secrets.md](../../docs/secrets.md)).
- Retrofit, Room and DataStore `suspend` APIs are **main-safe** — no `withContext` needed around them. Blocking
  APIs (`java.io` streams, `ContentResolver` queries, image decoding) run on the injected
  `dispatchers.io`; CPU-heavy mapping on `dispatchers.default`.

### 2. First table — creating `:core:database` (Room 3)

Run this once, in the first slice that persists data:

1. `core/database/build.gradle.kts`:
   ```kotlin
   plugins {
       id("android-forge.android.library")
       id("android-forge.hilt")
       id("android-forge.room")          // KSP + androidx.room3 + bundled SQLite + DAO-test deps
   }
   android {
       namespace = "<base>.core.database"
   }
   dependencies {
       implementation(project(":core:model"))
   }
   ```
2. `settings.gradle.kts`: `include(":core:database")`; `core/data/build.gradle.kts`: `implementation(project(":core:database"))`
   above the `// android-forge:core-data-deps` marker.
3. Entity, DAO, database, Hilt module:
   ```kotlin
   @Entity(tableName = "photos")
   data class PhotoEntity(
       @PrimaryKey val id: String,
       val title: String,
       val description: String?,
       val favorite: Boolean,
   )

   @Dao
   interface PhotoDao {
       @Query("SELECT * FROM photos ORDER BY title")
       fun observeAll(): Flow<List<PhotoEntity>>

       @Query("SELECT * FROM photos WHERE id = :id")
       suspend fun byId(id: String): PhotoEntity?

       @Upsert
       suspend fun upsertAll(photos: List<PhotoEntity>)

       @Query("UPDATE photos SET favorite = :favorite WHERE id = :id")
       suspend fun setFavorite(id: String, favorite: Boolean)
   }

   @Database(entities = [PhotoEntity::class], version = 1, exportSchema = true)
   abstract class AppDatabase : RoomDatabase() {
       abstract fun photoDao(): PhotoDao
   }

   @Module
   @InstallIn(SingletonComponent::class)
   internal object DatabaseModule {
       @Provides
       @Singleton
       fun provideAppDatabase(@ApplicationContext context: Context): AppDatabase = Room
           .databaseBuilder<AppDatabase>(context, "app.db")
           .setDriver(BundledSQLiteDriver())
           .setQueryCoroutineContext(Dispatchers.IO)   // Room's own I/O context — the one allowed Dispatchers.* outside RealDispatcherProvider
           .build()

       @Provides
       fun providePhotoDao(database: AppDatabase): PhotoDao = database.photoDao()
   }
   ```
   (Imports: `androidx.room3.*`, `androidx.sqlite.driver.bundled.BundledSQLiteDriver`.)
4. Commit `core/database/schemas/` — Room's exported schema history. Every shipped schema change bumps
   `version` and adds a migration (`@Database(autoMigrations = [AutoMigration(from = 1, to = 2)])`, or a
   `Migration` whose `suspend fun migrate(connection: SQLiteConnection)` runs SQL), tested with `room3-testing`'s
   `MigrationTestHelper`.

Room 3 notes: DAO functions are `suspend` unless they return `Flow`; type converters are
`@ColumnTypeConverter`/`@ColumnTypeConverters`; transactions are `withWriteTransaction { }`.

### 3. Preferences (`:core:datastore`)

The template's `UserPreferencesDataSource` is the pattern: one `DataStore<Preferences>` per file, provided
`@Singleton` by `DataStoreModule`; reads `.catch { if (it is IOException) emit(emptyPreferences()) else throw it }`
so they never throw; writes may throw (the repository maps them). Add a key to the existing data source when it
belongs to the same preferences file; a new concern gets its own file and data source. Typed data: a
kotlinx-serialization JSON `Serializer<T>` with `DataStoreFactory`. Secrets: encrypt the serializer with Tink —
never `EncryptedSharedPreferences`.

### 4. The repository: where exceptions become `DomainError`

Both boundaries already ship — call them, don't re-implement them:

- `:core:network`'s `suspend fun <T> catchNetwork(block: suspend () -> T): Result<T, DomainError>` —
  `CancellationException` rethrown first; `HttpException` → `Network.Http(status, code = null)`; `IOException`
  → `Network.Connectivity` (offline, DNS, timeouts); anything else → `Unknown(message)` (e.g. a body that
  doesn't parse). Logged with `Timber.w`.
- `:core:data`'s `catchStorage { }` — the same shape for Room, DataStore and file I/O: `CancellationException`
  rethrown first, everything else → `Unknown(message)`.

An offline-first repository — Room is the single source of truth, the network refreshes it:

```kotlin
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

internal fun PhotoDto.toEntity() = PhotoEntity(id = id, title = title, description = description, favorite = favorite)

internal fun PhotoEntity.toModel() = Photo(id = PhotoId(id), title = title, description = description, favorite = favorite)
```

and its binding in `DataModule`: `@Binds fun bindsPhotoRepository(impl: OfflineFirstPhotoRepository): PhotoRepository`.

- **Every data-source call goes through a boundary helper.** Nothing a library throws reaches `:core:domain`.
  Meaningful answers are decided before the boundary (404 → `null` in the data source; `null` → `NotFound` in
  the repository; an API error code → the area's typed error).
- It is **kotlin-result's** `runCatching` (`com.github.michaelbull.result.runCatching`), never the stdlib's, and
  `mapError` **rethrows `CancellationException` first, always**. Don't hand-roll `catch (e: Exception)` for the
  same job.
- A failure that is a *value* (a probe answering `null`) may use `try`/`catch` that rethrows
  `CancellationException` first, with a comment saying why every failure means the same thing there.
- Streams never throw: Room/DataStore flows, `.catch { }` where a source can fail.
- A `cause` is the exception message, for logs. The UI never shows it.
- Work that must outlive a screen (an upload, a sync) is WorkManager (`@HiltWorker`, opt-in) or an injected
  application-scope `CoroutineScope` — never a scope the repository creates and never cancels.

## Tests

- **Repository** (`core/data/src/test`): against fakes of its data sources and DAO — `internal class FakePhotoDao : PhotoDao`
  over a `MutableStateFlow`, `FakePhotoRemoteDataSource` with a `failWith: Throwable?` knob. Cover the mapping
  and **every error the repository can return**, plus cancellation once per helper
  (`assertFailsWith<CancellationException>`):
  ```kotlin
  @Test
  fun aDroppedConnectionBecomesConnectivity() = runTest {
      val repository = OfflineFirstPhotoRepository(FakePhotoDao(), FakePhotoRemoteDataSource().apply { failWith = IOException("offline") })

      assertEquals(Err(DomainError.Network.Connectivity), repository.refresh())
  }
  ```
- **Remote data source** (`core/network/src/test`): a real Retrofit over `MockWebServer` (`okhttp-mockwebserver3`):
  enqueue `MockResponse.Builder().code(200).body("""[{"id":"1","title":"a"}]""").build()`, assert the DTOs; a 503
  throws `HttpException`. `CatchNetworkTest` already covers the helper's own mapping.
- **DAO** (`core/database/src/test`): Robolectric + in-memory Room on the **framework** driver (the bundled one has
  no host-JVM native library under Robolectric):
  ```kotlin
  @RunWith(AndroidJUnit4::class)
  class PhotoDaoTest {
      @Test
      fun upsertedPhotosAreObservedInTitleOrder() = runTest {
          val database = Room.inMemoryDatabaseBuilder<AppDatabase>(ApplicationProvider.getApplicationContext<Context>())
              .setDriver(AndroidSQLiteDriver())
              .build()
          database.photoDao().upsertAll(listOf(entity("2", "b"), entity("1", "a")))
          assertEquals(listOf("a", "b"), database.photoDao().observeAll().first().map { it.title })
          database.close()
      }
  }
  ```
- **DataStore** (`core/datastore/src/test`): a real store on a temp file —
  `PreferenceDataStoreFactory.create(scope = backgroundScope) { tmpFolder.newFolder().resolve("x.preferences_pb") }`.
- Never the real network; never mocks of interfaces you own.
- Tag a test that covers an OpenSpec scenario (offline data shown, a failed refresh keeps the cache, …) with
  `// Scenario: <exact name>` — `android-qa` traces coverage through the tag.

## Before you hand it on

- `:core:data` has no public declarations; no DTO, entity, `Response` or `Preferences` appears in a `:core:domain`
  signature; only `:core:data` depends on `:core:network` / `:core:database` / `:core:datastore`.
- No exception escapes a repository: every data-source call goes through `catchNetwork` / `catchStorage`
  (or a commented value-`try`) that rethrows `CancellationException` first.
- No `Dispatchers.*` outside `RealDispatcherProvider` (and Room's `setQueryCoroutineContext`).
- Each repository is `@Binds`-bound in `DataModule`; its tests cover every error it can return plus cancellation.
- While iterating, the module you touched: `./gradlew :core:data:testDebugUnitTest` (also `:core:network:`,
  `:core:database:`, `:core:datastore:testDebugUnitTest`); before pushing `./gradlew spotlessApply`, then
  `./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true`.
