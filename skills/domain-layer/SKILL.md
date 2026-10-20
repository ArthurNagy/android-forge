---
name: domain-layer
description: Write or change domain code in an android-forge project (its CLAUDE.md says "android-forge project rules") — :core:model entities and value types without defaults, :core:domain use cases with @Inject constructors returning kotlin-result's Result<T, DomainError>, one repository interface per domain type, the sealed DomainError and an area's DomainError.Typed errors, DispatcherProvider, fakes and entity builders in :core:testing, and use-case tests. Use when adding a business rule or validation, a new domain entity or value type, a use case, a repository interface or an error type, writing a use-case test, deciding whether logic belongs in the domain layer, or when an OpenSpec task touches :core:domain or :core:model.
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
use case → wiring (nothing to do — § 5) → fake and entity builder in `:core:testing` → tests. Each step compiles on its own; `:core:data` and feature work can
start once the interface exists.

Each step — the compiling example plus its rules — is a file in `references/` next to this one; read the ones the
task needs (when reading this file directly instead of invoking the skill, they are under
`<claude_plugin_root>/skills/domain-layer/references/`):

1. [Entities and value types (`:core:model`)](references/entities.md) — no default values, immutable, IDs as value
   classes, no presentation.
2. [Errors: built-in cases, plus the area's typed errors](references/errors.md) — the sealed `DomainError`, an
   area's `DomainError.Typed` errors, when a new built-in case is warranted.
3. [Repository interfaces](references/repository-interfaces.md) — one per domain type, `suspend` + `Result` for
   one-shot operations, `Flow` streams that never throw, domain types only.
4. [Use cases](references/use-cases.md) — public `@Inject` constructor, one `operator fun invoke`, business rules,
   failures as values, `coroutineBinding`, kotlin-result imports.
5. **Wiring** — nothing to register: Hilt constructs `@Inject` use cases on demand. The repository interface is
   bound to its implementation in `:core:data`'s `DataModule` (`@Binds`).
6. [Fake and entity builder in `:core:testing`](references/fakes-and-builders.md) — a fake that behaves like the
   real thing with `seed` / `nextError` knobs, one builder per entity.
7. [Tests](references/tests.md) — the happy path and each error per use case, Turbine for streams,
   `TestDispatcherProvider(testScheduler)`, `// Scenario:` tags.

## Before you hand it on

- `:core:model` / `:core:domain` import nothing outside the allowed list; nothing references `Dispatchers.*`.
- Entities have no default values. Use cases are public with public `@Inject` constructors.
- Transport and generic failures use the built-in `DomainError` cases; the area's own failures are its sealed
  `DomainError.Typed` errors, each one a screen will react to.
- Each new use case has tests for success and every error it can return; each fake matches its interface.
- `./gradlew :core:domain:test` while iterating. Before pushing: `./gradlew spotlessApply`, then the CI gate
  `./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true` (85% line coverage).
