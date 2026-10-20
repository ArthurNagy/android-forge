---
name: github-release-artifacts
description: This skill should be used in an android-forge project (its CLAUDE.md says "android-forge project rules") when cutting or tagging a release, bumping versionCode/versionName, setting up or debugging the v* release workflow that attaches every app module's AAB/APK to a GitHub Release, upload-key signing secrets or a signed release build, keeping R8 mappings, running pre-release checks (play-policy-insights, r8-analyzer, Baseline Profile), or moving to Firebase App Distribution or per-form-factor Play tracks.
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

R8 `mapping.txt` per module rides in the workflow artifact — needed to retrace release stack traces, but workflow
artifacts expire (90 days by default). Keep each release's mappings as long as that release is in users' hands:
attach them to the GitHub Release renamed per module (`app-mapping.txt`, `wear-mapping.txt`, … — add them to the
release step's `files:`), or set `retention-days` on the upload and document it. Crashlytics/Sentry plugins upload
mappings themselves. Locally, `android describe --project_dir=.` lists every module's output paths.

## Before tagging

1. Bump `versionCode`/`versionName` in each app module, in a commit that goes through the normal PR gate. The
   version follows [release.md](../../docs/release.md) § Versioning (`git cliff --bumped-version` computes it from the
   commits). Version codes must be unique across the listing: `:app` counts from 1, `:wear` from `100_000_001`,
   `:tv` from `200_000_001`, `:automotive` from `300_000_001`.
2. `./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true` green on `main`, bump
   included.
3. `./gradlew assembleRelease` locally once per release cycle — R8 problems only show in release builds; the
   `r8-analyzer` skill audits keep rules when something is stripped or the APK grew.
4. `play-policy-insights` skill — permissions, data collection and declarations vs Play policy (before any store release).
5. Baseline Profile regenerated when startup paths changed (`./gradlew :app:generateReleaseBaselineProfile` on a
   device, `:benchmarks` opt-in) and committed.
6. The `android-qa` agent passed on every form factor the release touches.

Then tag: `git tag -a v<version> -m "Release v<version>"`. An agent may create the annotated tag locally; **pushing
it publishes the release, so `git push origin v<version>` is the user's** (or an agent's only after the user's
explicit yes in that session).

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
- **Release body empty**: no commits between this tag and the previous one (the same commit tagged twice), or only
  merge commits (`cliff.toml` skips them on purpose). Unconventional commits still appear, under **Other**.

## Manual release (no CI) — user-run

`gh release create` pushes the tag and publishes the Release, so this block is run by the user (or by an agent only
after the user's explicit yes in that session). Sign with the same injected properties CI uses — the app modules
have no `signingConfig` (or first add the `signing.properties` block from [release.md](../../docs/release.md)
§ Keystore policy); without one of the two the build produces unsigned artifacts:

```bash
./gradlew bundleRelease assembleRelease \
  -Pandroid.injected.signing.store.file="$HOME/.android-keystores/<project>.keystore" \
  -Pandroid.injected.signing.store.password="…" \
  -Pandroid.injected.signing.key.alias="release" \
  -Pandroid.injected.signing.key.password="…"
ls */build/outputs/apk/release/   # *-release.apk, never *-release-unsigned.apk
gh release create v<version> --title "v<version>" --notes "$(git cliff --latest --strip header)" \
  */build/outputs/bundle/release/*.aab */build/outputs/apk/release/*-release.apk
```
