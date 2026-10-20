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
  and prepares its output (sample code removed, `mipmap-anydpi-v26` merged, manifest wired to `MainApplication` and the
  template's backup rules, `includeBuild("build-logic")`, root build reduced to `android-forge.root`) — into a
  non-empty directory too, without overwriting; `ensure-sdk` installs compileSdk 37. **minSdk 29** by default (31/33
  offered); the conventions refuse < 26 (`java.time` without desugaring).
- **LICENSE from canonical texts** (`overlay/licenses/`: MIT, Apache-2.0, Proprietary) with year and holder filled in.
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
  Robolectric SDK pin; root `unitTests` / `coverageReport` / `coverageVerify` (JaCoCo ≥ 85%, Robolectric-run Compose
  counted; Android classes from AGP's Variant API, and the gate fails rather than pass blind when a module contributes
  no classes or execution data, when nothing is measured, or on product flavors).
- **Gates**: Android Lint (warnings = errors) with Slack's compose-lints, Spotless + ktlint + compose-rules, JaCoCo, Roborazzi screenshot
  verification (phone + tablet goldens committed in `src/test/screenshots/`, compared with a small cross-OS tolerance
  set by `:core:testing`'s `ScreenshotTolerancePlugin`; `record-goldens.yml` re-records on Linux on demand). CI runs
  `spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true` with a read-only token; release builds
  every app module. The gitleaks pre-commit hook scans resources (`strings.xml`) — only images, fonts, goldens and
  build output are skipped.
- **Merge guard v5** for the autonomous loop: a bash launcher + an embedded python3 shell lexer (stdlib, ≥ 3.8). It
  checks the PR and repository a merge really targets, unwraps wrappers and aliases, denies force pushes in every
  spelling, protects its own files and `openspec/AUTOLOOP.md` from every Claude caller in the enforce modes, denies
  subagent-posted gate verdicts, and in the enforce modes denies any command it can't parse that mentions a merge,
  push, ref, token, guard file or `ready`. The loop posts every review, issue and commit text through quoted-heredoc
  files.
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
  visibility, tests, a11y, adaptive) with Google's migration skills — its per-layer recipes live in `docs/migration.md`;
  the `build` layer renders the foundations first, pins the toolchain and raises minSdk to 29 after asking.
- `/android-forge-add-library` discovers through `android docs` + Google Maven + Maven Central and installs a library's
  skill tier; `/android-forge-bump-stack` cross-checks with `android studio version-lookup`.
- ADRs 0001–0009 (Orbit, Hilt, modules, Nav 3, Result, DispatcherProvider, Lint over detekt, JaCoCo, app module per
  form factor) — 0003 spells out what `:core:model`, `:core:domain`, `:core:data` and the storage/network modules each
  hold; 0007 and 0008 cite the open detekt 2.0 / Kover issues that keep them out.
- **Parent issues instead of epics** (diverges from kmp-forge): work too big for one PR stays a parent issue split into
  GitHub sub-issues (`gh issue create --parent`, gh ≥ 2.94); `issues.sh next` skips any issue with sub-issues — no
  `epic` label. The `android-architect` designs parent issues and single issues the product owner marks
  `design: needed` (a new module, data source or library, form factor, or cross-cutting concern).
- **Layer skills** (`domain-layer`, `data-layer`, `presentation-layer`): rules and a recipe index in `SKILL.md`, the
  compile-checked recipes in `references/`.

### Validated
- After the independent review's fixes (minSdk 29, merge guard v5), every flow run literally from the final docs into
  paths with a space, gate green at 85%:
  - `/android-forge-init` with the network + benchmarks opt-ins at 99.2% line coverage; + the Room First table
    recipe, `photo-detail` (key argument) and `gallery` (start destination) features and the Gallery/Photo slice copied
    from the three layer skills at 95.5% (`:app:assembleRelease` passes R8).
  - Form factors: Wear + TV through init itself (98.3%; `:wear`/`:tv`/`:app` release builds pass R8); Auto (POI) +
    Automotive + widgets + glasses + XR + desktop + Cast added one by one, then a feature taking over the start
    destination with the glasses entry point intact (94.2%); init + widgets + Wear + TV at minSdk 29 and 31 (96.2%);
    templated messaging refused for Automotive, `<uses name="notification"/>` for Auto.
  - `/android-forge-adopt` on a stock `android create` project (minSdk 24): Phase A, then the `build` layer at minSdk
    29 — configures and `assembleDebug` passes; the remaining compose-rules finding in its UI code is the `a11y`
    layer's.
  - Merge guard: a hook-JSON harness of 1037 checks (every listed bypass DENY in the enforce modes, the loop's own
    commands ALLOW, `log` never denies) on `/bin/bash` 3.2 + python 3.9, bash 5.3 + python 3.15, and GNU coreutils
    first; the add-autoloop smoke check through the wired `settings.json` command.
- At the 85% gate, after the PR review fixes: the bare scaffold at 99.1% line coverage (the new `AppThemeTest` covers
  the theme no other scaffold test reached) and 97.0% after `photo-detail`; `:wear` + `:tv` at 97.4%; `:car` +
  `:automotive` + `:widget` + `:glasses` + the XR and desktop manifest lines at 93.2% — that project's
  `AppNavigationTest` crashed with the glasses entry point on Home (`isProjectedDeviceConnected` needs a dispatcher,
  which a composition's context lacks under the Compose test rule) until `LaunchOnGlassesButton` took the lifecycle
  scope's context. Slack compose-lints fails `lint` on a composable without a modifier parameter.
- At the earlier 75% gate: `android create` (Android CLI 1.0.16625370) + the init steps into a path with a space; the
  full gate green on the bare scaffold (79.6% coverage) and after `photo-detail` (kebab) + `gallery` features, the network and benchmarks
  opt-ins, the Room First table recipe, and a Photo slice built from the three layer skills' code (43 tests, 86.6%
  coverage).
- On emulators through the Android CLI: launch, navigation through `@IntoSet` entries, rotation and process-death
  restore of the Nav 3 back stack (phone); the Hilt graph with Room + Retrofit + DataStore and the list-detail scene
  (unfolded foldable).
- Form-factor templates rendered per their recipes, gate green: `:wear` + `:tv` (55 tests, 89.6% coverage);
  `:car` + `:automotive` + `:widget` + `:glasses` + the XR and desktop manifest lines in one project (56 tests, 82.95%;
  `:app` and `:automotive` release builds pass R8).
- On emulators: Wear OS (`wearos_large_round`); TV (`tv_1080p`, D-pad focus move + select read back through
  `android layout`); AAOS (`automotive_1408p_landscape_with_play`: `CarAppActivity` renders the ListTemplate, Hilt on
  `CarAppService`); desktop windowing (`desktop_medium`: free-form window, two panes when maximized).
- Not run on a device: Android Auto (Desktop Head Unit), XR headset, display glasses, placing the widget on a home
  screen (no long-press in the CLI), the caption-bar tint (needs an API 35+ desktop image), Cast.
