---
description: Refresh gradle/libs.versions.toml against the latest stable versions of every locked-stack library.
---

# /android-forge-bump-stack

Queries Maven Central + Google Maven for the latest stable versions of every locked-stack lib, produces a diff against the project's current `gradle/libs.versions.toml`, and proposes a single commit.

## Flow

### 1. Fetch latest versions

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fetch-latest-versions.sh" toml > "${TMPDIR:-/tmp}/android-forge-latest.toml"
```

This emits a `[versions]` block keyed exactly like the project's catalog: the toolchain/Jetpack keys `android create` owns (`androidGradlePlugin`, `kotlin`, `androidxComposeBom`, `androidxCore`, `androidxActivity`, `androidxLifecycle`, `nav3Core`, `lifecycleViewmodelNav3`, `coroutines`, the `androidxTest*` keys, `junit`) plus the overlay's keys (`ksp`, `hilt`, `androidxHilt`, `orbitMvi`, `kotlinResult`, `kotlinxSerialization`, `androidxDatastore`, `material3Adaptive`, `coil`, `timber`, `turbine`, `robolectric`, `roborazzi`, `spotless`, `ktlint`, `composeRules`, `jacoco`, the opt-ins and the form-factor libraries). "Latest" means the highest purely numeric release in version order — `-alpha`/`-beta`/`-rc` builds are skipped, except for keys whose pin tracks a pre-release line (the XR glasses keys — and for those, propose only the versions the current official glasses docs pin: `android docs search "glimmer setup"`; Google tells you to stay on them even when newer pre-releases exist). Compose artifacts follow the BOM (`androidxComposeBom`); never pin one individually.

When Android Studio is running (`android studio check`), cross-check the proposed versions with `android studio version-lookup <group:artifact>…` (it also knows Gradle plugin ids and `gradle`); a mismatch with the Maven metadata is surfaced to the user, the metadata wins.

It also emits a `[wrapper]` section with the latest stable Gradle release (`gradle = "…"`) — the wrapper isn't a catalog key.

### 2. Read the current project catalog

```bash
PROJECT_LIBS="<projectRoot>/gradle/libs.versions.toml"
```

### 3. Compute the diff

For each key in `${TMPDIR:-/tmp}/android-forge-latest.toml`'s `[versions]` block:

- If the key exists in `PROJECT_LIBS` and the version is newer, mark for bump.
- If the key exists and the version is older (e.g. you pinned an older minor on purpose), skip — surface a note.
- If the key doesn't exist in `PROJECT_LIBS`, skip (this project doesn't use that lib).
- If the script returned `# WARN <key> ... not found`, skip — surface a warning.

### 4. Present the diff to the user

Use `AskUserQuestion` to confirm the bump, showing the full list of changes:

```
Libraries to bump:
  - orbitMvi: 12.0.1 → 12.1.0
  - coil: 3.6.3 → 3.7.0
  - androidxComposeBom: 2026.09.00 → 2026.10.00

Continue?
```

### 5. Apply the bump

Use the `Edit` tool with `replace_all = false` to update each `[versions]` entry in `PROJECT_LIBS`. Use unique anchor text (the full `key = "old_version"` line) for safety.

If `[wrapper] gradle` is newer than the version in `gradle/wrapper/gradle-wrapper.properties`'s `distributionUrl`, include it in the confirmation and update it the supported way — run the wrapper task **twice** (the second run regenerates the wrapper jar/scripts with the new version):

```bash
./gradlew wrapper --gradle-version <latest> --distribution-type bin
./gradlew wrapper --gradle-version <latest> --distribution-type bin
```

Never go below android-forge's floor (Gradle 9.8.1 — `pin-toolchain`; AGP 9.4.1 and the other floors in `${CLAUDE_PLUGIN_ROOT}/overlay/gradle/libs.versions.toml.additions.tmpl`).

### 6. Build to verify

One Bash call (timeout 600000); the log keeps the full output and the exit code is Gradle's:

```bash
cd "<projectRoot>" || exit 1; LOG="${TMPDIR:-/tmp}/android-forge-bump-stack-gradle.log"
./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true --console=plain > "${LOG}" 2>&1; rc=$?
tail -50 "${LOG}"; echo "exit=${rc}"
```

`exit=0` → step 7. Otherwise surface the failure verbatim — user decides whether to revert or fix forward. **Do not** auto-revert.

### 7. Surface breaking-change notes

For each major bump (e.g. `2.x → 3.x`), suggest the user check the library's release notes for migration steps. Don't try to migrate automatically.

### 8. Suggest commit

Print a Conventional Commit message ready to use:

```
chore(deps): bump locked stack to latest stable

- orbitMvi 12.0.1 → 12.1.0
- coil 3.6.3 → 3.7.0
- androidxComposeBom 2026.09.00 → 2026.10.00
```

User commits when they're ready (don't auto-commit — give them a chance to amend after manual review).

## Notes

- This is the **only** automated dependency-update path in android-forge. No Renovate/Dependabot.
- Versions are bumped one project at a time. If you have multiple android-forge projects, run this in each.
- `kotlin`, `ksp` and `hilt` move together (KSP and Dagger must read the Kotlin version's metadata); `androidGradlePlugin` bumps can need a newer Gradle wrapper and convention-plugin changes — surface them clearly.
- `robolectric`: a release that supports a newer Android SDK lets you raise `sdk=` in `core/testing/src/main/resources/robolectric.properties` (keep it ≤ the newest SDK Robolectric supports).
- A Compose BOM / Material bump can change pixels: screenshot verification may fail. Inspect the diffs (`build/outputs/roborazzi`), then re-record only if the change is expected (`./gradlew recordRoborazziDebug`) and say so in the commit.
- A `androidxCarApp` bump: re-sync `car/src/main/res/values/car_hosts_allowlist.xml` with the library's `hosts_allowlist_sample` (it's private to the library, so android-forge keeps a copy).
- Also refresh the project's Android skills: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" update "<project-root>"`.
