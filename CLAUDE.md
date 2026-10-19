# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`android-forge` is a **Claude Code plugin** — not an Android project. It scaffolds and guides pure-Android Jetpack
Compose apps on a locked, opinionated stack (Hilt, Orbit state-only, Navigation 3 with `api`/`impl` features,
kotlin-result, Room 3 / Retrofit 3 opt-ins) across phones, tablets, foldables and opt-in form factors (Wear OS, TV,
Android Auto, Android Automotive OS, XR headsets/glasses, Googlebook/desktop, Cast, widgets). It drives Google's
**Android CLI** (`android create`, `sdk`, `emulator`, `run`, `layout`, `screen`, `input`, `docs`, `skills`, `studio`) and
installs Google's **Android agent skills** into projects. Kotlin only appears in `overlay/**/*.kt.tmpl` templates.

Sibling of kmp-forge (`../kmp-forge`, the KMP version) — same software factory, Android-only stack. See
§ Shared lineage.

Distribution: self-contained marketplace (`.claude-plugin/marketplace.json`, `source: "./"`):
`/plugin marketplace add arthurnagy/android-forge` then `/plugin install android-forge@android-forge`.

## Commands

```bash
# Render a template in isolation (only OVERLAY_VARS are substituted — see scripts/apply-overlay.sh)
BASE_PACKAGE=com.foo.app APP_NAME=Foo envsubst '${BASE_PACKAGE} ${APP_NAME}' < overlay/app/src/main/kotlin/MainActivity.kt.tmpl

# Create a real project and apply the overlay by hand (what /android-forge-init does) — a scratch target
bash scripts/android-new.sh ensure-sdk 37
bash scripts/android-new.sh create Foo com.foo.app 26 "/tmp/af/Foo"
BASE_PACKAGE=com.foo.app bash scripts/apply-overlay.sh render-module core.domain overlay/modules/core/domain /tmp/af/Foo/core/domain com/foo/app
bash scripts/apply-overlay.sh patch-settings /tmp/af/Foo "core:model,core:domain"
MIN_SDK=26 bash scripts/apply-overlay.sh patch-libs /tmp/af/Foo overlay/gradle/libs.versions.toml.additions.tmpl   # appends + raises floors
bash scripts/apply-overlay.sh pin-toolchain /tmp/af/Foo                                                            # wrapper + heap

# Android skills (tiers are defined in scripts/skills.sh) and emulators per form factor
bash scripts/skills.sh tiers
bash scripts/skills.sh install /tmp/af/Foo baseline wear
bash scripts/avd.sh status            # name | status | ensure <phone|tablet|desktop|foldable|wear|tv|automotive|xr|glasses>

# Latest stable versions of every catalog key (Google Maven + Maven Central + services.gradle.org)
bash scripts/fetch-latest-versions.sh toml

# GitHub-issue work queue (inside a project with a GitHub origin)
bash scripts/issues.sh labels
bash scripts/issues.sh next --approvers alice,bob
```

**Validation = a real project.** There is no test runner here. A change to templates, conventions or scripts is
validated by scaffolding into a scratch dir (the steps of `/android-forge-init`, a path **with a space**), then:
`./gradlew spotlessApply && ./gradlew recordRoborazziDebug && ./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true`,
plus a feature added via the add-feature recipe (use a kebab-case name like `photo-detail`), plus `android run` on an
emulator (rotate + background-kill-relaunch). Form-factor templates: render them per their recipe, gate green, and
run the module on its `scripts/avd.sh` emulator. The 0.1.0 entry in `CHANGELOG.md` records what was validated.

## Repo layout

```
.claude-plugin/        plugin.json + marketplace.json
commands/              /android-forge-* slash commands (prompts)
agents/                android-feature-builder, android-form-factor-builder, android-reviewer, android-migrator,
                       android-qa, android-architect, android-product-owner, android-spec-critic,
                       android-loop-{proposer,implementer,code-reviewer,fixer}
skills/                domain-layer · data-layer · presentation-layer (per-layer coding recipes; examples must compile),
                       backlog-issue-authoring, mvp-spec-authoring, adr-authoring, conventional-commits,
                       git-cliff-changelog, github-release-artifacts, driving-ci-green
scripts/
  android-new.sh       create (android create + prepare) | prepare | ensure-sdk
  apply-overlay.sh     render [--no-clobber] | render-module | patch-settings | patch-libs (append + raise floors) | pin-toolchain
  skills.sh            Google Android skill tiers: tiers | install | check | update
  avd.sh               emulators per form factor: name | status | ensure
  fetch-latest-versions.sh   for /android-forge-bump-stack
  issues.sh            GitHub issues as the work queue
overlay/
  root/                CLAUDE.md.tmpl, .gitignore, .editorconfig (ktlint rules), cliff.toml
  ci/                  pr.yml (the gate), release.yml (every app module), spec-link.yml
  git/                 PR/issue templates (issue-form labels are a contract), .gitleaks.toml, pre-commit hook
  openspec/            config.yaml.tmpl — android-forge's OpenSpec rules
  product/             MVP_SPEC.md.tmpl + DECISIONS/0001..0009
  build-logic/         precompiled convention plugins android-forge.{android.application, android.library[.compose],
                       jvm.library, feature.api, feature.impl, hilt, room, spotless, root}
  gradle/              libs.versions.toml.additions.tmpl (every alias the conventions use + toolchain floors)
  app/                 :app composition root (MainApplication, MainActivity, MainActivityViewModel, AppNavigation, Home)
  modules/core/<m>/    :core:{model,domain,data,datastore,designsystem,ui,navigation,testing}
  modules/feature/{api,impl}/   the add-feature templates (Feature*.kt.tmpl → <Name>*.kt)
  optional/network/    :core:network (Retrofit/OkHttp/catchNetwork) · optional/benchmarks/ (:benchmarks)
  form-factors/<ff>/   per form factor: libs.versions.toml.additions + module templates / README recipes
  autoloop/            merge-guard.sh + settings.json + AUTOLOOP.md.tmpl
docs/                  source-of-truth conventions linked from every scaffolded CLAUDE.md (incl. form-factors/,
                       android-cli.md, quality.md)
```

## How a scaffold works

`/android-forge-init`: questions (name, package, minSdk, form factors, opt-ins, license, git, spec workflow) →
env file (`typeset -p … > "${TMPDIR}/android-forge-init.env"`, `source`d by every later block) →
`android-new.sh create` (`android create empty-activity` + `prepare`: sample code removed, `mipmap-anydpi-v26` merged
at minSdk ≥ 26, manifest gets `.MainApplication` + backup rules, `includeBuild("build-logic")`, root build reduced to
`id("android-forge.root")`) → render root/ci/git/product/openspec → copy build-logic → `render-module` every core
module and `:app` → `patch-settings` → `patch-libs` (appends aliases, raises `android create`'s older pins) →
`pin-toolchain` → opt-ins (network, benchmarks; Room = the data-layer skill's First table recipe later) → form factors
(the form-factor-builder agent) → `skills.sh install baseline` → `spotlessApply`, `recordRoborazziDebug`, the gate →
git (+ `gh repo create`/push only on an explicit yes).

Features: `/android-forge-add-feature` → `android-feature-builder` renders `modules/feature/{api,impl}`, renames
`Feature*`, includes both modules, adds `implementation(project(":feature:<name>:impl"))` above `:app`'s
`// android-forge:feature-modules` marker. Entries reach `NavDisplay` through Hilt `@IntoSet`
(`Set<EntryProviderInstaller>`, declared with `@Multibinds` in `:core:navigation` so an app with no features builds).

## Locked-stack rules the agents/templates enforce

Canonical text: `docs/architecture.md`, `docs/stack.md`, `docs/testing.md`. Encoded in `agents/android-reviewer.md`
(audit), `agents/android-feature-builder.md` (generation), `agents/android-migrator.md` (refactor recipes),
`skills/{domain,data,presentation}-layer/` (recipes), and the templates.

- **Modules**: `:core:model`/`:core:domain` are JVM modules. A feature `impl` depends on `:core:domain`, `:core:model`,
  `:core:ui`, `:core:designsystem`, `:core:navigation` and other features' `:api` — **never `:core:data`** (or the
  storage/network modules) and never another `impl`. Only app modules depend on `:core:data`. Keys live only in `:api`.
  One app module per device type (`:wear`, `:tv`, `:automotive`), sharing core but not phone UI.
- **Hilt**: constructor injection; `@AndroidEntryPoint` only on framework entry points; `@HiltViewModel`; `internal`
  Hilt modules beside what they bind; `@IntoSet` entry builders; `@AssistedInject` for key arguments.
- **Orbit state-only**: `OrbitContainerHost<S, S, Nothing>`, `orbitContainer(S.Initial) { load() }`, consumable slots
  (`pendingNavigation: NavKey?`, `@StringRes pendingMessage: Int?`) + `onXConsumed()`; never `postSideEffect`; lambda
  params in effects via `rememberUpdatedState`.
- **Nav 3**: `@Serializable` keys; `rememberNavBackStack(StartKey)` + `Navigator`; list-detail scene strategy; screens
  get lambdas, never the Navigator; `navigator.backOrNull()` for the root's missing Back.
- **Result + sealed DomainError** (kotlin-result): built-in cases worded by `:core:ui`'s `toMessage()` + `DomainError.Typed`;
  exceptions stop at `catchNetwork { }` / `catchStorage { }`, which rethrow `CancellationException` first.
- **DispatcherProvider**: no `Dispatchers.*` outside `RealDispatcherProvider` (and Room's `setQueryCoroutineContext`).
- **Visibility**: `internal` by default; `:core:data` and feature `impl`s expose nothing public; no constructor defaults
  on entities/State; `State.Initial`; use-case constructors stay public.
- **Resources**: every Android module's keys carry its `resourcePrefix`; strings in `values/strings.xml`.
- **Adaptive**: no orientation/resizability locks; window-size layouts; edge-to-edge; phone + tablet goldens per screen.
- **Tests**: JUnit 4 + Robolectric (SDK pinned to 36 by `:core:testing`'s `robolectric.properties`, JDK 21 launcher,
  `jdk.internal.access` export — set by the conventions); fakes over mocks; Orbit harness; ViewModels built outside
  `setContent`.
- **Gate**: `spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true` (Lint warnings = errors;
  ktlint + compose-rules; JaCoCo ≥ 75% aggregated by `android-forge.root`).

## Conventions for editing this repo

- Conventional Commits; releases tagged from `main`; changelog by git-cliff.
- **zsh-safe shell in every prompt**: the Bash tool may run zsh. Brace variables (`"${FEATURE_NAME}:api"` — an unbraced
  `$FEATURE_NAME:a…` is a zsh modifier and silently mangles the path) and quote every path (the user's projects folder
  contains a space).
- **Plugins come from build-logic**: modules apply `id("android-forge.*")` / bare ids; never `alias(libs.plugins.x)`
  (AGP & co. are already on the classpath via build-logic). A new plugin = a catalog `[libraries]` entry for its
  artifact + `implementation(...)` in `overlay/build-logic/build.gradle.kts`.
- **New overlay variable**: the `.tmpl`, `OVERLAY_VARS` in `scripts/apply-overlay.sh`, and the export block of the
  command that renders it (init step 2; add-feature / add-form-factor / add-autoloop). Unset vars render as "".
- **Changing a locked-stack rule** — update in lockstep: `docs/<area>.md` (canonical), `agents/android-reviewer.md`,
  `agents/android-feature-builder.md`, `agents/android-migrator.md`, the layer skill (examples must keep compiling —
  re-validate them in a scratch project), the templates under `overlay/`, and `overlay/openspec/config.yaml.tmpl` if it
  names the rule.
- **Catalog**: every alias a convention plugin looks up (`catalog.findLibrary("…")`) must exist in
  `overlay/gradle/libs.versions.toml.additions.tmpl`; version keys there double as floors; `scripts/fetch-latest-versions.sh`
  lists the same keys for bump-stack.
- **Form-factor matrix** — lockstep: `docs/form-factors/<ff>.md`, `overlay/form-factors/<ff>/`,
  `agents/android-form-factor-builder.md`, `commands/android-forge-add-form-factor.md`, `scripts/avd.sh` (AVD +
  image), `agents/android-qa.md` (device selection table), the tier in `scripts/skills.sh`, and `docs/android-cli.md`.
- **Skill tiers** — `scripts/skills.sh` is the source of truth; mirror it in `docs/android-cli.md`, README, and
  `/android-forge-add-library`'s library → tier table.
- **Autoloop material** — lockstep: `commands/android-forge-next-increment.md`, `agents/android-loop-*.md`,
  `agents/android-spec-critic.md`, `overlay/autoloop/`, `scripts/issues.sh`, `docs/autoloop.md`. The issue form's field
  labels (`### Problem`, `Acceptance criteria`, `Out of scope`, `Notes`, `Depends on`, `Needs a human first`,
  `Change name`) are parsed by `issues.sh`, the loop workers and `/android-forge-refine`; the `ready` label is applied
  only by a human (merge-guard denies it); the `### 🤖 <gate> — round r/3 — <VERDICT>` review header is shared by the
  orchestrator, its resume jq and `merge-guard.sh`; the hook command in `overlay/autoloop/settings.json` stays quoted;
  bump `merge-guard.sh`'s `# version:` on every change.
- Other string contracts: `// android-forge:feature-modules` and `// android-forge:core-data-deps` markers;
  `// Scenario: <name>` test tags; the "android-forge project rules" line the agents/doctor look for; `TODO(android-forge)`.
- Docs are the source of truth and ship via GitHub `main` (scaffolded CLAUDE.md links them).
- Never push to GitHub, create remotes, or enable branch protection from a command without the user's explicit yes in
  that session.

## Shared lineage with kmp-forge

android-forge was bootstrapped from kmp-forge v0.6.0 (`4362f52`). These files are near-identical in both plugins
(renamed `kmp-` → `android-`); a fix in one usually applies to the other — port it by hand and note it in both
changelogs:

- `scripts/issues.sh`, `overlay/autoloop/{merge-guard.sh,settings.json,AUTOLOOP.md.tmpl}`, `overlay/git/**`
- `commands/{…-spec,…-refine,…-next-increment,…-add-autoloop}.md`
- `agents/{…-product-owner,…-architect,…-spec-critic,…-loop-proposer,…-loop-implementer,…-loop-code-reviewer,…-loop-fixer}.md`
- `skills/{backlog-issue-authoring,mvp-spec-authoring,adr-authoring,conventional-commits,git-cliff-changelog,driving-ci-green}`
- `docs/{product-workflow,autoloop,git-conventions,upgrade-policy}.md`

Everything else (stack, modules, templates, build-logic, QA, reviewer, migrator, layer skills) diverges by design.
