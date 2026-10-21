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
core/network/src/main/kotlin/<base-path>/core/network/     (opt-in; "First API call" in recipe 1)
  NetworkModule.kt              OkHttpClient, Json, Retrofit (+ @Provides for each service)
  CatchNetwork.kt               the network boundary: IOException / HttpException (404 → NotFound) / other → DomainError
  photo/
    PhotoApi.kt                 internal Retrofit service interface
    PhotoDto.kt                 @Serializable wire shape (public: the data source returns it)
    PhotoRemoteDataSource.kt    public interface + internal Retrofit implementation (@Binds in a module)
core/database/src/main/kotlin/<base-path>/core/database/   (created by "First table", recipe 2)
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

Each step — the compiling example plus its rules — is a file in `references/` next to this one; read the ones the
task needs (when reading this file directly instead of invoking the skill, they are under
`<claude_plugin_root>/skills/data-layer/references/`). Skip the sources the repository doesn't use.

1. [Remote data source (`:core:network`)](references/remote-data-source.md) — DTO, Retrofit service, remote data
   source + its binding; **First API call** creates `:core:network` when the network opt-in wasn't picked at init.
2. [First table — creating `:core:database` (Room 3)](references/first-table.md) — once, in the first slice that
   persists data: module, entity, DAO, `AppDatabase`, `DatabaseModule`, exported schemas and migrations.
3. [Preferences (`:core:datastore`)](references/preferences.md) — a key on the existing data source or a new
   preferences file; typed data; secrets with Tink.
4. [The repository: where exceptions become `DomainError`](references/repository.md) — `catchNetwork` /
   `catchStorage`, the offline-first repository, mappers, the `DataModule` binding.
5. [Tests](references/tests.md) — repository over fakes (every error + cancellation), MockWebServer remote data
   source, Robolectric in-memory DAO, temp-file DataStore.

## Before you hand it on

- `:core:data` has no public declarations; no DTO, entity, `Response` or `Preferences` appears in a `:core:domain`
  signature; only `:core:data` depends on `:core:network` / `:core:database` / `:core:datastore`.
- No exception escapes a repository: every data-source call goes through `catchNetwork` / `catchStorage`
  (or a commented value-`try`) that rethrows `CancellationException` (and any `Error`) first.
- No `Dispatchers.*` outside `RealDispatcherProvider` (and Room's `setQueryCoroutineContext`).
- Each repository is `@Binds`-bound in `DataModule`; its tests cover every error it can return plus cancellation.
- While iterating, the module you touched: `./gradlew :core:data:testDebugUnitTest` (also `:core:network:`,
  `:core:database:`, `:core:datastore:testDebugUnitTest`); before pushing `./gradlew spotlessApply`, then
  `./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true` (85% line coverage).
