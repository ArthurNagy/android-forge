# Release

## Versioning

**SemVer.** Tag format `v<major>.<minor>.<patch>`.

- **Major**: breaking API or behavior change
- **Minor**: new feature, additive only
- **Patch**: bug fix, perf, docs

Conventional Commits drive the bump:
- `BREAKING CHANGE:` footer or `<type>!:` → major
- `feat:` → minor
- `fix:` / `perf:` → patch
- `chore:` / `docs:` / `test:` / `ci:` / `build:` / `refactor:` / `style:` → no version bump (still appear in changelog)

## Tagging

```
git tag -a v0.3.0 -m "Release v0.3.0"
git push origin v0.3.0
```

Tag push triggers `.github/workflows/release.yml`.

## Distribution tiers

### Default: GitHub Release artifacts

Every `v*` tag publishes a GitHub Release with the git-cliff changelog and, for **every app module**, the
signed AAB + APK (`app-release.aab`/`.apk`, plus `wear-release.*`, `tv-release.*`, `automotive-release.*` when
those form factors exist) — R8 `mapping.txt` files ride along in the workflow artifact. Sideload from the
Releases page; no store presence, zero infra.

### Beta tier (opt-in): Firebase App Distribution

Add the `com.google.firebase.appdistribution` plugin to the app module (via `build-logic` like every plugin)
or a CI step:

```yaml
firebase-android:
  needs: android
  runs-on: ubuntu-latest
  steps:
    - uses: actions/download-artifact@v8
      with: { name: android }
    - uses: wzieba/Firebase-Distribution-Github-Action@v1
      with:
        appId: ${{ secrets.FIREBASE_APP_ID_ANDROID }}
        serviceCredentialsFileContent: ${{ secrets.FIREBASE_SERVICE_ACCOUNT_JSON }}
        groups: testers
        file: app/build/outputs/apk/release/app-release.apk
```

### Play tier (opt-in): gradle-play-publisher

`com.github.triplet.play` (≥ 4.0 — required on AGP 9) uploads through the Play Developer API, no fastlane.
Put the plugin on build-logic's classpath (catalog key `playPublisher`) and apply it to each app module:

```kotlin
// app/build.gradle.kts (and wear/, tv/, automotive/)
plugins { id("com.github.triplet.play") }
play {
    serviceAccountCredentials.set(rootProject.file("play-service-account.json")) // written by CI from the secret
    track.set("internal")
}
```

```yaml
- name: Play service account
  run: echo '${{ secrets.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON }}' > play-service-account.json
- run: ./gradlew :app:publishReleaseBundle --track=internal
```

**One Play track per form factor.** Wear OS, Android TV and Android Automotive OS each have a dedicated
track (Play Console ▸ Release ▸ Advanced settings ▸ Form factors) and their app modules publish there with
the same `applicationId`. Android Auto, XR (same-APK) and desktop ship inside the phone APK; XR glasses
apps have no Play distribution yet. See each [form-factors/](form-factors/) page.

### Before a store release

- `play-policy-insights` skill — audit permissions, data collection and declarations against Play policy.
- `r8-analyzer` skill — keep rules: redundant or too-broad rules cost size.
- Baseline Profile regenerated (`./gradlew :app:generateReleaseBaselineProfile`, opt-in `:benchmarks`) when
  startup paths changed.
- The quality tier you claim (see [quality.md](quality.md)) checked by the `android-qa` agent on each form factor.

### When to add fastlane

Only for automated store screenshots across devices/locales or bulk listing metadata. gradle-play-publisher
covers uploads.

## Keystore policy

**Never commit the keystore.** Never commit `signing.properties`. Never commit `.env*` files.

Local:
- Generate keystore once with `keytool -genkey -v -keystore release.keystore -keyalg RSA -keysize 2048 -validity 25000 -alias release`
- Store at `<projectRoot>/release.keystore` (gitignored) or `~/.android-keystores/<project>.keystore`
- Create `signing.properties` (gitignored):
  ```
  storeFile=release.keystore
  storePassword=...
  keyAlias=release
  keyPassword=...
  ```
- `app/build.gradle.kts` reads it (local release builds only):
  ```kotlin
  val signingProps = Properties().apply {
      file("signing.properties").takeIf { it.exists() }?.inputStream()?.use(::load)
  }
  android {
      signingConfigs {
          create("release") {
              storeFile = signingProps["storeFile"]?.toString()?.let(::file)
                  ?: System.getenv("KEYSTORE_PATH")?.let(::file)
              storePassword = signingProps["storePassword"]?.toString() ?: System.getenv("KEYSTORE_PASSWORD")
              keyAlias = signingProps["keyAlias"]?.toString() ?: System.getenv("KEY_ALIAS")
              keyPassword = signingProps["keyPassword"]?.toString() ?: System.getenv("KEY_PASSWORD")
          }
      }
  }
  ```

CI:
- Encode keystore once: `base64 -i release.keystore | pbcopy`, paste into `ANDROID_KEYSTORE_BASE64` secret; add `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
- Workflow decodes to `$RUNNER_TEMP/release.keystore` and passes AGP's injected signing properties (`-Pandroid.injected.signing.store.file=… .store.password=… .key.alias=… .key.password=…` — what Android Studio's "Generate Signed Bundle" uses), so CI signs every AAB/APK **without** any `signingConfig` in the app modules. The `signing.properties` block above is only needed for local release builds.
- The `changelog-and-release` job declares `permissions: contents: write` (new repos default `GITHUB_TOKEN` to read-only) and runs only after the android job succeeded.
- Use **Play App Signing**: the keystore above is the *upload* key; Google holds the app signing key.

## Changelog (git-cliff)

`cliff.toml` at repo root (shipped by the overlay — `overlay/root/cliff.toml` is the full file). The part that decides what reaches the notes:

```toml
[git]
conventional_commits = true
filter_unconventional = false   # keep non-conventional commits…
filter_commits = false
commit_parsers = [
    # …except merge commits, skipped on purpose: they only restate a PR whose commits
    # (merge workflow) or squash commit (squash workflow) are already listed.
    { message = "^Merge (pull request|branch|remote-tracking branch) ", skip = true },
    { message = "^feat", group = "Features" },
    { message = "^fix", group = "Fixes" },
    { message = "^perf", group = "Performance" },
    { message = "^refactor", group = "Refactor" },
    { message = "^docs", group = "Documentation" },
    { message = "^chore", group = "Chore" },
    { message = "^build", group = "Build" },
    { message = "^ci", group = "CI" },
    { message = "^test", group = "Tests" },
    { message = "^style", group = "Style" },
    { message = "^[Rr]evert", group = "Reverts" },   # `revert: …` and git's `Revert "…"`
    { message = ".*", group = "Other" },             # catch-all: nothing disappears silently
]
```

Every commit since the last tag lands in exactly one group except GitHub/GitLab merge commits. A non-conventional subject still shows up (under **Other**) so a sloppy message is visible in review rather than silently missing from the release.

Release workflow runs `git-cliff --latest --strip header` to populate the GitHub Release body. Full `CHANGELOG.md` regenerated on each release via `git-cliff -o CHANGELOG.md` and committed back to `main` via a follow-up PR (optional — manual is fine for solo work).

## Hotfix flow

1. Branch off `main`: `fix/<urgent>`
2. PR + merge as usual
3. Tag a patch release: `v<current-minor>.<patch+1>`

No `release/*` branch unless you support multiple major versions concurrently.
