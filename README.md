# android-forge

A Claude Code plugin that scaffolds and guides **pure-Android** Jetpack Compose apps on a locked, opinionated stack —
phones, tablets and foldables by default; Wear OS, TV, Android Auto, Android Automotive OS, XR headsets and glasses,
Googlebook/desktop, Cast and widgets on opt-in.

The pure-Android sibling of [kmp-forge](https://github.com/arthurnagy/kmp-forge): the same software factory (spec →
issue backlog → OpenSpec → autonomous build loop with spec/code/QA gates → release), with Android-first libraries
and Google's own tooling.

## What it does

`android-forge` creates the base project with **Google's Android CLI** (`android create`), raises it to a tested
toolchain floor (AGP 9.4 with built-in Kotlin, Gradle 9.8, compile/target SDK 37), then overlays: convention plugins,
the `:core:*` + `:feature:*:{api,impl}` module shape, a working Hilt → DataStore → use case → Orbit slice, the gates
(Lint + compose-lints, ktlint + compose-rules, JaCoCo 85%, Roborazzi screenshots), CI, product docs and ADRs — and installs Google's
**Android agent skills** into the project, tiered by the form factors and capabilities it uses. Devices, emulators,
docs and versions go through the Android CLI too.

## Install

```
/plugin marketplace add arthurnagy/android-forge
/plugin install android-forge@android-forge
```

Needs the Android CLI (`/android-forge-doctor` checks and tells you how to install it), `envsubst`, `python3`, and
optionally `gh` and `openspec`.

## Slash commands

- `/android-forge-init` — create a project with `android create` and apply the overlay (form factors, opt-ins, skills, git)
- `/android-forge-adopt` — adopt android-forge into an existing Android project (non-destructive overlay + reviewer-led, layer-by-layer refactor)
- `/android-forge-add-feature <name>` — a `:feature:<name>:api` + `:impl` pair (screen, Hilt Orbit ViewModel, state, `@IntoSet` entries, tests, screenshots)
- `/android-forge-add-screen <feature> <screen>` — a screen inside an existing feature
- `/android-forge-add-form-factor <wear|tv|auto|automotive|xr|glasses|desktop|cast|widgets>` — add a device type or surface (module, manifest, catalog, skills, emulator)
- `/android-forge-add-library <query>` — find a Jetpack/Google (or Maven) library, add it to the catalog and module, install its skill tier
- `/android-forge-bump-stack` — refresh the catalog against the latest stable versions (Maven metadata + `android studio version-lookup`)
- `/android-forge-spec` — author `docs/MVP_SPEC.md`
- `/android-forge-refine <idea | #issues | --gaps>` — product-owner pass: workable backlog issues (+ an architect pass on parent issues and issues that need design); you approve with `ready`
- `/android-forge-doctor` — Android CLI, SDK, system images, emulators, JDKs, floors, skills, hooks, workflow
- `/android-forge-add-autoloop` — install the autonomous build loop (OpenSpec, GitHub-issue queue, merge-guard)
- `/android-forge-next-increment` — run ONE autonomous increment on the next `ready` issue; wrap with `/loop`

## Agents

`android-feature-builder` · `android-form-factor-builder` · `android-reviewer` · `android-migrator` · `android-qa`
(journeys on every form factor a change touches, through the Android CLI) · `android-architect` ·
`android-product-owner` · `android-spec-critic` · `android-loop-{proposer,implementer,code-reviewer,fixer}`.

## Skills

Plugin skills (load in an android-forge project when the work matches): `domain-layer` · `data-layer` ·
`presentation-layer` · `backlog-issue-authoring` · `mvp-spec-authoring` · `adr-authoring` · `conventional-commits` ·
`git-cliff-changelog` · `github-release-artifacts` · `driving-ci-green`.

Google's Android skills, installed per project in tiers (`scripts/skills.sh`): **baseline** — android-cli, adaptive,
navigation-3, navigation-event, edge-to-edge, testing-setup, jetpack-compose-performance, android-profiler,
android-intent-security, android-permissions-security, r8-analyzer, play-policy-insights; **form factors** — wear-compose-m3,
wear-widgets, leanback-to-compose-tv-migration, engage-sdk-integration, android-for-cars-parked-apps,
display-glasses-with-jetpack-compose-glimmer, media3-cast-integration, glance-canonical-layouts; **capabilities** —
camerax, appfunctions, ml-kit-genai-prompt-api, litert-runtime, restore-credentials, verified-email,
play-billing-library-version-upgrade; **adopt** — agp-9-upgrade, migrate-xml-views-to-jetpack-compose, styles.
See [docs/android-cli.md](docs/android-cli.md).

## Locked stack

| Concern | Choice |
|---|---|
| UI | Jetpack Compose + Material 3 (adaptive): window-size layouts, Nav 3 list-detail scenes, edge-to-edge |
| DI | Hilt (KSP) — constructor injection, `@HiltViewModel`, `@IntoSet` feature entries |
| State | Orbit MVI, state-only (consumable slots, never `postSideEffect`) |
| Navigation | androidx Navigation 3 — keys in `:feature:<name>:api`, entries in `:impl`, one saveable back stack |
| Modules | `:app` · `:core:{model,domain,data,datastore,designsystem,ui,navigation,testing}` · `:feature:<name>:{api,impl}` · one app module per extra device type |
| Errors | kotlin-result `Result<T, DomainError>`; `catchNetwork` / `catchStorage` boundaries |
| Persistence | DataStore (always) · Room 3 (opt-in, first table creates `:core:database`) |
| HTTP (opt-in) | Retrofit 3 + OkHttp 5 + kotlinx-serialization (`:core:network`) |
| Images · logging · time | Coil 3 · Timber · java.time |
| i18n | Android resources with per-module prefixes, per-app languages |
| Testing | JUnit 4 + Robolectric + Orbit test + Turbine + Compose UI Test v2 + Roborazzi (phone + tablet goldens) |
| Gates | Android Lint + Slack compose-lints (warnings = errors) · Spotless/ktlint + compose-rules · JaCoCo ≥ 85% |
| Toolchain | AGP ≥ 9.4.1 (built-in Kotlin), Gradle ≥ 9.8.1, Kotlin 2.4, KSP2, compile/target SDK 37 |
| Performance (opt-in) | Baseline Profiles + Macrobenchmark (`:benchmarks`) |
| Crash reporting | Play Vitals by default; Firebase Crashlytics or Sentry Android opt-in |
| Distribution | GitHub Releases (every app module); Firebase App Distribution / gradle-play-publisher (a Play track per form factor) opt-in |
| Devices | Google's Android CLI — `android emulator`, `run`, `layout`, `screen`, `input`; `scripts/avd.sh` for Wear/TV/AAOS/XR/foldable emulators |
| Work tracking | GitHub issues — `ready` (human-applied) = the backlog |
| Spec workflow | OpenSpec (default; plain docs opt-out), `spec-link` CI check |

## Documentation

[Architecture](docs/architecture.md) · [Stack](docs/stack.md) · [Form factors](docs/form-factors/) ·
[Android CLI & skills](docs/android-cli.md) · [Quality tiers](docs/quality.md) · [Testing](docs/testing.md) ·
[CI](docs/ci.md) · [Release](docs/release.md) · [Observability](docs/observability.md) ·
[Git conventions](docs/git-conventions.md) · [Product workflow](docs/product-workflow.md) ·
[Autonomous build loop](docs/autoloop.md) · [Secrets](docs/secrets.md) · [i18n & a11y](docs/i18n-a11y.md) ·
[Upgrade policy](docs/upgrade-policy.md)

## License

MIT — see [LICENSE](LICENSE).
