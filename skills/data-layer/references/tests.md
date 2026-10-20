# Tests

Use when testing a repository (fakes), a remote data source (MockWebServer), a DAO (Robolectric + in-memory Room) or a DataStore (temp file).

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
- **Remote data source** (`core/network/src/test`): a real Retrofit over `MockWebServer` — add
  `testImplementation(libs.okhttp.mockwebserver3)` to `core/network/build.gradle.kts` first (the alias is in the catalog):
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

      private fun entity(id: String, title: String) = PhotoEntity(id = id, title = title, description = null, favorite = false)
  }
  ```
- **DataStore** (`core/datastore/src/test`): a real store on a temp file —
  `PreferenceDataStoreFactory.create(scope = backgroundScope) { tmpFolder.newFolder().resolve("x.preferences_pb") }`.
- Never the real network; never mocks of interfaces you own.
- Tag a test that covers an OpenSpec scenario (offline data shown, a failed refresh keeps the cache, …) with
  `// Scenario: <exact name>` — `android-qa` traces coverage through the tag.
