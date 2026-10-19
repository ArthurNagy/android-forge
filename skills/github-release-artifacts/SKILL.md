---
name: github-release-artifacts
description: Configure and ship release artifacts for an android-forge project — signed AABs/APKs for every app module (:app, :wear, :tv, :automotive) attached to a GitHub Release on a v* tag, R8 mappings, the pre-release checks (play-policy-insights, r8-analyzer, Baseline Profile), and graduating to Firebase App Distribution or per-form-factor Play tracks via gradle-play-publisher. Use in an android-forge project (its CLAUDE.md says "android-forge project rules") when setting up release CI, debugging release uploads, cutting a release, or planning distribution.
---

# Release artifacts — android-forge default distribution

The default tier: zero infra. A `v*` tag push builds signed artifacts for every app module and attaches them to a
GitHub Release whose body git-cliff writes. Canonical: the plugin's [release.md](../../docs/release.md) and
[ci.md](../../docs/ci.md).

## Workflow

`.github/workflows/release.yml` (from the overlay):

```yaml
on:
  push:
    tags: ['v*']
jobs:
  android:               # ./gradlew bundleRelease assembleRelease with AGP injected signing → artifact "android"
  changelog-and-release: # git-cliff body + softprops/action-gh-release with every app module's AAB/APK
```

`bundleRelease`/`assembleRelease` run in every app module, so `:wear`, `:tv` and `:automotive` ship automatically
once they exist — they share the upload key and the applicationId with `:app`.

## Required secrets (signing)

| Secret | Encoding | What |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | base64 of the upload keystore | decoded to `$RUNNER_TEMP/release.keystore` |
| `ANDROID_KEYSTORE_PASSWORD` · `ANDROID_KEY_ALIAS` · `ANDROID_KEY_PASSWORD` | plain | passed as `-Pandroid.injected.signing.*` |

```bash
base64 -i release.keystore | pbcopy   # paste into ANDROID_KEYSTORE_BASE64
```

Use Play App Signing: this is the **upload** key.

## Artifacts

| Module | AAB | APK |
|---|---|---|
| `:app` | `app/build/outputs/bundle/release/app-release.aab` | `app/build/outputs/apk/release/app-release.apk` |
| `:wear` · `:tv` · `:automotive` | `<module>/build/outputs/bundle/release/<module>-release.aab` | `<module>/build/outputs/apk/release/<module>-release.apk` |

R8 `mapping.txt` per module rides in the workflow artifact (needed to read release stack traces; Crashlytics/Sentry
plugins upload it themselves). Locally, `android describe --project_dir=.` lists every module's output paths.

## Before tagging

1. `./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true` green on `main`.
2. `./gradlew assembleRelease` locally once per release cycle — R8 problems only show in release builds; the
   `r8-analyzer` skill audits keep rules when something is stripped or the APK grew.
3. `play-policy-insights` skill — permissions, data collection and declarations vs Play policy (before any store release).
4. Baseline Profile regenerated when startup paths changed (`./gradlew :app:generateReleaseBaselineProfile` on a
   device, `:benchmarks` opt-in) and committed.
5. The `android-qa` agent passed on every form factor the release touches.
6. Bump `versionCode`/`versionName` in each app module (keep `:wear`/`:tv`/`:automotive` versionCodes distinct from
   `:app`'s when they share a Play listing — Play requires unique version codes per track/APK).

Then `git tag -a v0.3.0 -m "Release v0.3.0" && git push origin v0.3.0` (the user pushes; agents never do).

## Body of the Release

git-cliff (`cliff.toml`) from Conventional Commits — see the `git-cliff-changelog` skill.

## Graduating

- **Testers** → Firebase App Distribution (release.md § Beta tier).
- **Play** → gradle-play-publisher (`com.github.triplet.play` ≥ 4.0 on AGP 9, through build-logic): **each form factor
  publishes to its own track** — Wear OS, Android TV and Android Automotive OS have dedicated tracks (Play Console ▸
  Release ▸ Advanced settings ▸ Form factors); Android Auto, XR and desktop ride in the phone APK. XR glasses apps
  have no Play distribution yet.

## Troubleshooting

- **`No files found`** in the upload step: the glob didn't match — check `android describe` output for the real paths
  (a module renamed, a flavor added).
- **Signing fails in CI but works locally**: an empty decoded keystore (bad base64) or a missing secret.
- **Release crashes but debug works**: R8 stripped something reflective — add a targeted keep rule (or the library's
  consumer rules are missing); `r8-analyzer` helps; read the mapping-retraced stack trace.
- **Release body empty**: no Conventional Commits since the last tag.

## Manual release (no CI)

```bash
./gradlew bundleRelease assembleRelease   # with signing.properties for local signing
gh release create v0.3.0 --title "v0.3.0" --notes "$(git cliff --latest --strip header)" \
  */build/outputs/bundle/release/*.aab */build/outputs/apk/release/*.apk
```
