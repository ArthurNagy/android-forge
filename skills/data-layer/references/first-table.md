# First table — creating `:core:database` (Room 3)

Use in the first slice that persists data: it creates `:core:database` — entity, DAO, `AppDatabase`, Hilt module, exported schemas.

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
