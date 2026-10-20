# CI / GitHub Actions

Every scaffolded project ships four workflows (`overlay/ci/`): **`pr.yml`** (the gate), **`release.yml`**
(signed artifacts on a `v*` tag), **`spec-link.yml`** (`feat:` PRs that change production code carry an
OpenSpec change) and **`record-goldens.yml`** (manual: re-record the screenshot goldens on Linux). Each sets a
read-only `GITHUB_TOKEN` (`permissions: contents: read`); only the release job that creates the GitHub Release
gets `contents: write`.

## `pr.yml` — the gate

Runs on every PR to `main`; required by branch protection. One Ubuntu job:

| Step | Command | Fails when |
|---|---|---|
| Format | `./gradlew spotlessCheck` | ktlint or a compose-rules check fails (`spotlessApply` fixes formatting; compose-rules findings need a code change) |
| Lint | `./gradlew lint` | any Android Lint warning, Slack compose-lints included (warnings are errors; dependency-freshness checks are off) |
| Tests + screenshots + coverage | `./gradlew coverageVerify -Proborazzi.test.verify=true` | a local test fails, a screenshot differs from (or lacks) its golden, or aggregated line coverage < 85% |
| Assemble | `./gradlew assembleDebug` | any app module (`:app`, `:wear`, `:tv`, `:automotive`) fails to build |

Then `coverageReport` runs and the reports (JaCoCo HTML, Lint HTML, test reports, Roborazzi diffs) are
uploaded as the `reports` artifact — on failure too.

- **JDK**: `setup-java` installs Temurin **17 and 21**. Gradle runs on 21 (the last one listed is `JAVA_HOME`);
  the JVM modules (`:core:model`, `:core:domain`, feature `api`s) compile and run their tests on a 17 toolchain;
  the Android modules' local tests run on a JDK 21 launcher (Robolectric's SDK 35+ runtimes need it) — both set by
  the convention plugins. Both present = no toolchain download.
- **`gradle/actions/setup-gradle@v6`** caches Gradle state (accepts Gradle's Terms of Use; pin `@v5` to opt out).
- `concurrency` cancels superseded runs.
- **Mirror it locally** before pushing — the same four commands, or in one go:
  `./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true`.
  Driving a red PR to green from the CLI (watching checks, reading failures without dumping logs) is the
  plugin's `driving-ci-green` skill.
- **Instrumented tests** are not in the gate. When a project grows `androidTest` suites, add an opt-in job
  on Gradle Managed Devices (`testOptions.managedDevices.localDevices { create("pixel9api36") { device = "Pixel 9"; apiLevel = 36; systemImageSource = "aosp-atd" } }`
  → `./gradlew pixel9api36DebugAndroidTest`) gated on a repository variable — it needs KVM on the runner.

## Screenshot goldens across OSes

Goldens (`<module>/src/test/screenshots/`, Roborazzi on Robolectric) are verified on **Linux** — `pr.yml` runs on
`ubuntu-latest`. Robolectric's rendering can differ slightly between macOS and Linux (font rasterisation,
anti-aliasing); the build conventions compare with a small tolerance, but a golden recorded on a Mac can still
fail CI with no UI change. Then re-record on Linux instead of loosening the comparison:

1. Push the branch; Actions → **Record goldens** → *Run workflow* on that branch (`record-goldens.yml`: the same
   JDK setup as the gate, then `./gradlew recordRoborazziDebug`).
2. Download the `goldens` artifact, unzip it at the repository root (it keeps the `<module>/src/test/screenshots/`
   paths), review the PNGs and commit them.

Use it whenever the gate's Roborazzi diff (in the `reports` artifact) shows pixel noise rather than a real
change — typically a project's first PR when its goldens were recorded on a Mac, or after a Robolectric / Compose /
Roborazzi bump that shifts rendering.

## `release.yml`

Runs on a `v*` tag push:

1. **android** — decodes the upload keystore, runs `./gradlew bundleRelease assembleRelease` with AGP's
   injected signing properties (no signing config or keystore path in the repo), and uploads every app
   module's AAB, APK and R8 `mapping.txt`.
2. **changelog-and-release** — git-cliff renders the notes for the tag; `softprops/action-gh-release`
   attaches the AABs/APKs to a GitHub Release.

Opt-in tiers (Firebase App Distribution, Play tracks via gradle-play-publisher) add steps; see
[release.md](release.md).

## `spec-link.yml`

A `feat:` PR whose diff touches production code — `app/`, `core/*/`, `feature/*/{api,impl}/`, `wear/`,
`tv/`, `automotive/`, `car/`, `glasses/`, `widget/` under `src/main/` — must also change
`openspec/changes/` or `openspec/specs/`, or carry the `no-spec` label. Skipped in projects without
`openspec/`; non-`feat:` PRs pass.

## Coverage

JaCoCo through AGP (`enableUnitTestCoverage` on debug) in every Android module and the `jacoco` plugin on JVM
modules; the **root convention** `android-forge.root` aggregates them (`coverageReport`, `coverageVerify`).

- Every module except `:core:testing` is aggregated automatically — new features included.
- Robolectric-run code counts (the conventions set `includeNoLocationClasses`), so screen tests cover Compose.
- Excluded: Compose singletons, serializers, Hilt modules (`*Module`), `MainApplication`/`MainActivity`, feature
  `api` modules, `*EntriesKt`, `DomainError`, design tokens, `RealDispatcherProvider`; Hilt-generated Java is never
  in the class set.
- Changing the bound or the excludes: `build-logic/src/main/kotlin/android-forge.root.gradle.kts` (project-owned
  after scaffolding) — never with CI flags.

## Required secrets

| Secret | Purpose | Required when |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | Upload keystore (base64) | release |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password | release |
| `ANDROID_KEY_ALIAS` | Key alias | release |
| `ANDROID_KEY_PASSWORD` | Key password | release |
| `FIREBASE_APP_ID_ANDROID` / `FIREBASE_SERVICE_ACCOUNT_JSON` | Firebase App Distribution | beta tier |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | gradle-play-publisher | Play tier |
| `GOOGLE_SERVICES_JSON` | `app/google-services.json` (written in CI) | Firebase Crashlytics/Perf opt-in |
| `SENTRY_AUTH_TOKEN` · `SENTRY_DSN` | mapping upload · runtime DSN | Sentry opt-in |

See [secrets.md](secrets.md) for where each lives and how the build reads it.

## Branch protection

Settings → Branches → rule for `main`: require a PR; require the `PR / gate` status (and `Spec link /
spec-link` with OpenSpec); require linear history; restrict pushes. android-forge never enables it for you.
With the autonomous loop, the account `gh` is authenticated as needs a bypass for its bookkeeping pushes to `main`
(steering files, archives) — see [autoloop.md](autoloop.md).
