---
description: Check the local Android toolchain against what an android-forge project needs — Android CLI, SDK platform and form-factor system images, emulators, JDKs, Gradle/AGP floors, the project's Android skills, git hooks and the spec/issue workflow. Diagnostic; asks before fixing anything.
---

# /android-forge-doctor

Diagnostic. Surfaces drift between the machine and what the project (or a new android-forge project) expects, with a
remediation command for each problem. It **changes nothing by itself**; at the end it may offer fixes, each applied only
after an explicit yes.

Run inside an android-forge project (its CLAUDE.md says "android-forge project rules") for the full check, or anywhere
before `/android-forge-init` for the toolchain part (steps 1–4). The Bash tool may run zsh — brace variables.

## Flow

### 1. Android CLI

```bash
command -v android && android --version && android info
```

`android` is Google's Android CLI — android-forge creates projects (`android create`), manages the SDK, emulators,
devices, docs and skills through it. Missing → ✗ with the installer for the host (macOS arm64:
`curl -fsSL https://dl.google.com/android/cli/latest/darwin_arm64/install.sh | bash`; macOS Intel `…/darwin_x86_64/…`;
Linux `…/linux_x86_64/…`), then `android init`. Present → suggest `android update` when `android update --help` shows
one is available (don't run it).

### 2. Android SDK

```bash
android sdk list 2>/dev/null | sed -n '/Installed packages/,/Available/p' | grep -E "platforms/android-3[67]|build-tools/3[67]|emulator|platform-tools"
command -v avdmanager || ls "$(android info sdk 2>/dev/null)/cmdline-tools/latest/bin/avdmanager" 2>/dev/null
```

Expected: `platforms/android-37*` (compileSdk 37), recent `build-tools`, `emulator`, `platform-tools`, and
`cmdline-tools` (for `avdmanager`, which non-phone AVDs need). Remediation:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/android-new.sh" ensure-sdk 37`, `android sdk install cmdline-tools/latest`.

**Per form factor** (from CLAUDE.md § Form factors): is the system image the QA emulator needs installed, and does
the AVD `bash "${CLAUDE_PLUGIN_ROOT}/scripts/avd.sh" name <form-factor>` prints exist? (`avd.sh status` answers both.)

```bash
android emulator list
bash "${CLAUDE_PLUGIN_ROOT}/scripts/avd.sh" status       # each form factor: image installed? AVD present?
```

Missing → ⚠ with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/avd.sh" ensure <form-factor>` (downloads a system image —
gigabytes; say so). Android Auto needs the Desktop Head Unit (`android sdk install extras/google/auto`).

### 3. Devices

```bash
adb devices -l          # the CLI has no device list; adb is used for nothing else
```

Report emulators and physical devices. A **physical** device is the user's: android-forge never installs to it
without asking (the `android-qa` agent is the exception, under its own rules).

### 4. JDKs

```bash
java -version 2>&1 | head -1
/usr/libexec/java_home -V 2>&1 | grep -E "17|21" ; ls ~/.gradle/jdks 2>/dev/null
```

Expected: a JDK that runs Gradle 9.8 (17+); toolchains **17** (JVM modules compile with it) and **21** (local tests:
Robolectric's SDK 35+ runtimes need it). Missing toolchains are provisioned by Gradle's foojay resolver on the first
build (network) — ⚠ only offline.

### 5. Gradle, AGP, Kotlin floors (in a project)

```bash
grep distributionUrl gradle/wrapper/gradle-wrapper.properties
grep -E '^(androidGradlePlugin|kotlin|ksp|hilt|androidCompileSdk|androidTargetSdk|androidMinSdk) *=' gradle/libs.versions.toml
grep -q 'includeBuild("build-logic")' settings.gradle.kts && grep -q 'android-forge.root' build.gradle.kts && echo "build-logic wired"
```

Expected: Gradle ≥ 9.8.1, AGP ≥ 9.4.1, Kotlin 2.4.x with a matching KSP 2.3.x and Hilt ≥ 2.59.2, compile/target SDK
37, build-logic wired. Remediation: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" pin-toolchain .` (wrapper + heap) and
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/apply-overlay.sh" patch-libs .
"${CLAUDE_PLUGIN_ROOT}/overlay/gradle/libs.versions.toml.additions.tmpl"` (raises catalog floors, never lowers), or
`/android-forge-bump-stack`. `kotlin-android` or `kapt` plugins present → ✗ (AGP 9 built-in Kotlin + KSP; the
`agp-9-upgrade` skill migrates).

### 6. Android skills (in a project)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" check . baseline <one tier per form factor in CLAUDE.md>
android skills list --project=. --agent=claude-code 2>/dev/null | head -40
```

Missing → ⚠ `bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" install . <tier>`. Stale → `skills.sh update .`
(both write into `.claude/skills/` — committed with the project).

### 7. Android Studio (optional)

```bash
android studio check 2>&1 | head -3
```

Running → `version-lookup` and `render-compose-preview` are available to bump-stack / feature-builder. Not running → ✓
(optional).

### 8. Signing (if `signing.properties` exists)

Required keys present (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`), `storeFile` exists. Never print
values.

### 9. Git hooks + secrets

`.git/hooks/pre-commit` exists and is executable; `gitleaks` on PATH; `google-services.json`, `*.keystore`,
`signing.properties` git-ignored.

### 10. Spec & work workflow

```bash
[[ -d openspec ]] && openspec --version && node --version
grep -q "android-forge project rules" openspec/config.yaml 2>/dev/null && echo "android-forge rules present"
gh --version | head -1
gh label list --limit 200 --json name --jq '[.[].name] | map(select(. == "ready" or . == "in-progress" or . == "no-spec"))'
```

- `gh` < 2.94 → ✗: the work queue reads GitHub sub-issues (`--parent`, `subIssuesSummary`). Remediation: `brew upgrade gh`.

- `openspec/` present → `openspec` ≥ 1.14. Remediation: `brew upgrade openspec` / `npm install -g @fission-ai/openspec@latest`.
- `openspec/config.yaml` without android-forge's rules → ⚠, merge `${CLAUDE_PLUGIN_ROOT}/overlay/openspec/config.yaml.tmpl`.
- Workflow labels missing on GitHub → ⚠, `bash "${CLAUDE_PLUGIN_ROOT}/scripts/issues.sh" labels` (writes to GitHub).

### 11. Gradle smoke test (in a project)

```bash
./gradlew help -q --console=plain 2>&1 | tail -10
```

Configuration must succeed (plugins resolve from build-logic). Don't run `--refresh-dependencies`.

## Output

Per section: ✓ OK / ⚠ Drift (expected vs actual + remediation) / ✗ Missing (+ remediation). Example:

```
✓ Android CLI 1.0.16625370 (sdk: ~/Library/Android/sdk)
✓ SDK: platforms/android-37.0, build-tools 37.0.0, emulator, cmdline-tools
⚠ Wear OS image missing (android-37.0/android-wear-signed) — bash <plugin>/scripts/avd.sh ensure wear  (~2 GB)
✓ Devices: emulator-5554 (medium_phone)
✓ JDK toolchains: 17, 21
✓ Gradle 9.8.1 · AGP 9.4.1 · Kotlin 2.4.21 · KSP 2.3.12 · Hilt 2.60.1 · SDK 37/37/26 · build-logic wired
⚠ Android skills: wear-widgets missing — bash <plugin>/scripts/skills.sh install . wear
✓ Android Studio: not running (optional)
✓ git hooks: pre-commit installed, gitleaks on PATH
✓ OpenSpec 1.15.0 · android-forge rules present · labels present
✓ Gradle configuration OK
```

Then a summary count. If anything is fixable from the plugin (SDK platform, an AVD, skills, labels, catalog floors),
offer the fixes via `AskUserQuestion` (multi-select) and run only what the user picks.
