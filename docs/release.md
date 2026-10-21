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

`git cliff --bumped-version` computes the next version from the commits since the last tag.

## Cutting a release

This is the canonical flow; the `github-release-artifacts` skill summarises it and links here.

1. **Version.** `git cliff --bumped-version` (and `git cliff --unreleased` for the notes it will produce).
2. **Bump commit.** In every app module's `defaultConfig` (`app/build.gradle.kts`, plus `wear/`, `tv/`,
   `automotive/` when they exist), raise `versionName` to the new version and `versionCode` by one (each module
   counts in its own range — § Version codes across form factors). One commit, `chore(release): v<x.y.z>`, through
   a PR and the normal gate. Regenerating `CHANGELOG.md` (`git cliff --tag v<x.y.z> -o CHANGELOG.md`) may ride
   along — optional.
3. **Checks** on `main` with the bump merged:
   - the CI gate green: `./gradlew spotlessCheck lint coverageVerify assembleDebug -Proborazzi.test.verify=true`;
   - `./gradlew assembleRelease` locally once per release cycle — R8 problems only show in release builds; the
     `r8-analyzer` skill audits keep rules when something is stripped or the APK grew;
   - before any store release, the `play-policy-insights` skill — permissions, data collection and declarations
     against Play policy;
   - the Baseline Profile regenerated when startup paths changed (`./gradlew :app:generateReleaseBaselineProfile`
     on a device, opt-in `:benchmarks`) and committed;
   - the quality tier you claim (see [quality.md](quality.md)) checked by the `android-qa` agent on every form
     factor the release touches.
4. **Tag** the merged bump commit: `git tag -a v<x.y.z> -m "Release v<x.y.z>"`. An agent may create the annotated
   tag locally.
5. **Push the tag** — `git push origin v<x.y.z>`. Pushing publishes the release, so this step is the user's (an
   agent's only after the user's explicit yes in that session). The push triggers `.github/workflows/release.yml`,
   which builds, signs and attaches every app module's AAB/APK under a git-cliff release body.

### Hotfix flow

1. Branch off `main`: `fix/<urgent>`; PR + merge as usual.
2. Cut a patch release — § Cutting a release with `v<major>.<minor>.<patch+1>`; the bump commit still raises every
   app module's `versionCode`.

No `release/*` branch unless you support multiple major versions concurrently.

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

### Version codes across form factors

Every APK/AAB of one Play listing needs a unique `versionCode`. It lives in each app module's `defaultConfig`, and
android-forge offsets the form-factor apps: `:app` counts from 1, `:wear` from `100_000_001`, `:tv` from
`200_000_001`, `:automotive` from `300_000_001` — the release bump commit raises each module's own code (the
form-factor templates start there).

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

Release workflow runs `git-cliff --latest --strip header` to populate the GitHub Release body. A committed
`CHANGELOG.md` is optional: regenerate it in the release bump commit (§ Cutting a release, step 2) — manual is fine
for solo work.
