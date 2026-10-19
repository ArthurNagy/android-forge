# Changelog

All notable changes to `android-forge` will be documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-19

First release: the pure-Android sibling of kmp-forge, bootstrapped from kmp-forge v0.6.0 (`4362f52`) — the
software factory (spec, GitHub-issue backlog with human-only `ready`, product owner and architect, OpenSpec,
autonomous build loop with spec/code/QA gates and merge-guard, CI, git-cliff, ADRs, release) carried over; the stack,
modules, templates, build logic, QA and review rebuilt for Android.

### Added
- **Project creation through Google's Android CLI** — `scripts/android-new.sh` runs `android create empty-activity`
  and prepares its output (sample code removed, `mipmap-anydpi-v26` merged at minSdk ≥ 26, manifest wired to
  `MainApplication` and the template's backup rules, `includeBuild("build-logic")`, root build reduced to
  `android-forge.root`); `ensure-sdk` installs compileSdk 37.
- **Locked stack**: Jetpack Compose + Material 3 adaptive, Hilt (KSP2), Orbit 12 state-only, androidx Navigation 3
  with `:feature:<name>:{api,impl}` and Hilt `@IntoSet` entry builders (`@Multibinds`-declared), kotlin-result
  `Result<T, DomainError>` with `catchNetwork`/`catchStorage` boundaries, DataStore, Coil 3, Timber, java.time,
  Android resources with per-module `resourcePrefix`; opt-ins Retrofit 3 + OkHttp 5 (`:core:network`), Room 3 (First
  table recipe), Baseline Profiles + Macrobenchmark (`:benchmarks`).
- **Modules**: `:app` + `:core:{model,domain,data,datastore,designsystem,ui,navigation,testing}` (Google's
  modularization shape; features see only `:core:domain`), one app module per extra device type. The scaffold ships a
  working DataStore → repository → use case → Orbit ViewModel slice (the stored theme mode).
- **Build logic**: precompiled conventions `android-forge.{android.application, android.library[.compose],
  jvm.library, feature.api, feature.impl, hilt, room, spotless, root}`; AGP 9.4 built-in Kotlin; JDK 21 test launcher +
  Robolectric SDK pin; root `unitTests` / `coverageReport` / `coverageVerify` (JaCoCo ≥ 75%, Robolectric-run Compose
  counted).
- **Gates**: Android Lint (warnings = errors), Spotless + ktlint + compose-rules, JaCoCo, Roborazzi screenshot
  verification (phone + tablet goldens committed in `src/test/screenshots/`). CI runs
  `spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true`; release builds every app module.
- **Form factors** — `/android-forge-add-form-factor` + the `android-form-factor-builder` agent: Googlebook/desktop,
  XR headset, XR display glasses, Android Auto, Android Automotive OS, TV, Wear OS, Cast, home-screen widgets;
  `docs/form-factors/`, `docs/quality.md` (Google's quality tiers).
- **Android skills, per project, in tiers** — `scripts/skills.sh` (baseline, form-factor and capability tiers) installs
  Google's skills into `.claude/skills/`; agents load them for platform work; doctor checks them.
- **Emulators per form factor** — `scripts/avd.sh` (phone/tablet/desktop via `android emulator create`; foldable, Wear,
  TV, AAOS, XR, glasses via `android sdk install` + avdmanager).
- **`android-qa`** drives devices only through the Android CLI (`android describe`, `run`, `layout`, `screen`,
  selector-based `android input`), runs journeys on every form factor a change touches, and handles the multi-display
  screenshot quirk on foldables.
- **`android-reviewer`** enforces the module, Hilt, Orbit, Nav 3, Result, adaptive, resource-prefix and manifest rules
  and runs Google's intent/permission security skills on manifest and IPC changes; **`android-migrator`** moves an
  existing Android app onto the stack layer by layer (build, modules, dispatchers, result, repos, hilt, orbit, nav,
  visibility, tests, a11y, adaptive) with Google's migration skills.
- `/android-forge-add-library` discovers through `android docs` + Google Maven + Maven Central and installs a library's
  skill tier; `/android-forge-bump-stack` cross-checks with `android studio version-lookup`.
- ADRs 0001–0009 (Orbit, Hilt, modules, Nav 3, Result, DispatcherProvider, Lint over detekt, JaCoCo, app module per
  form factor).

### Validated
- `android create` (Android CLI 1.0.16625370) + the init steps into a path with a space; the full gate green on the
  bare scaffold (79.6% coverage) and after `photo-detail` (kebab) + `gallery` features, the network and benchmarks
  opt-ins, the Room First table recipe, and a Photo slice built from the three layer skills' code (43 tests, 86.6%
  coverage).
- On emulators through the Android CLI: launch, navigation through `@IntoSet` entries, rotation and process-death
  restore of the Nav 3 back stack (phone); the Hilt graph with Room + Retrofit + DataStore and the list-detail scene
  (unfolded foldable).
