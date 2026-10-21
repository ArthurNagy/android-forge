# Secrets

## Principles

1. Never commit secrets. Never amend a commit that accidentally added one — rotate the secret instead.
2. Local secrets live in **gitignored** files. CI secrets live in **GitHub Actions Secrets**.
3. Both client-side (gitleaks) and server-side (GitHub Push Protection) scanning. Belt + suspenders.

## What counts as a secret

- Signing keystores and keystore passwords
- API keys (Sentry DSN, Firebase, Maps, third-party services)
- OAuth client secrets
- Service account JSON files — the Google Play Developer API key gradle-play-publisher publishes with, Firebase
- Any token or credential the app uses to authenticate

## Local layout

```
<projectRoot>/
├── release.keystore          ← gitignored (or ~/.android-keystores/<project>.keystore)
├── signing.properties        ← gitignored (local release builds only; CI uses injected signing)
├── local.properties          ← gitignored (SDK path + local-only build values)
├── app/google-services.json  ← gitignored (Firebase opt-in; CI writes it from a secret)
└── play-service-account.json ← gitignored (written by CI for gradle-play-publisher)
```

### `signing.properties`

```properties
storeFile=release.keystore
storePassword=<password>
keyAlias=release
keyPassword=<password>
```

Read by `app/build.gradle.kts` for local release builds (see [release.md § Keystore policy](release.md#keystore-policy)).

### Build-time values: `BuildConfig` fields from `local.properties` / environment

Runtime configuration the app needs at build time (a Sentry DSN, a Maps key, a non-default API base URL)
becomes an AGP `BuildConfig` field in the module that uses it — read from `local.properties` locally and
from an environment variable in CI, never hard-coded:

```kotlin
// core/network/build.gradle.kts (buildFeatures.buildConfig = true is already on there)
val localProps = Properties().apply {
    rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use(::load)
}
fun secret(name: String): String = localProps.getProperty(name) ?: System.getenv(name) ?: ""

android {
    defaultConfig {
        buildConfigField("String", "MAPS_API_KEY", "\"${secret("MAPS_API_KEY")}\"")
    }
}
```

A key that must reach the manifest (Maps) uses `manifestPlaceholders` the same way. Remember: anything
compiled into the APK is extractable — a real secret (a server credential) never belongs in the app; put it
behind your backend.

## CI secrets

Stored at: GitHub repo → Settings → Secrets and variables → Actions.

| Secret | Encoding | Purpose |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | base64 of `release.keystore` | Decoded to `$RUNNER_TEMP/release.keystore` at workflow start |
| `ANDROID_KEYSTORE_PASSWORD` | plain | Passed via env to Gradle |
| `ANDROID_KEY_ALIAS` | plain | Passed via env |
| `ANDROID_KEY_PASSWORD` | plain | Passed via env |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | raw JSON | Decoded to file for `firebase` CLI |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | raw JSON | Decoded for `gradle-play-publisher` |
| `GOOGLE_SERVICES_JSON` | raw JSON | Written to `app/google-services.json` (Firebase opt-in) |
| `SENTRY_DSN` | plain | Exported as env; becomes a `BuildConfig` field |
| `SENTRY_AUTH_TOKEN` | plain | Sentry Gradle plugin's mapping upload |

### Encoding keystore for CI

```bash
base64 -i release.keystore | pbcopy
# paste into ANDROID_KEYSTORE_BASE64 secret
```

### Decoding in workflow

```yaml
- name: Decode keystore
  run: echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$RUNNER_TEMP/release.keystore"
  env: { ANDROID_KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }} }
```

The release step passes AGP's injected signing properties pointing at it and signs every app module's AAB/APK.

## gitleaks (pre-commit)

`.gitleaks.toml` at the repo root extends gitleaks' default rules. Its allowlist skips only binary files and build
output — text resources stay scanned: a key pasted into `res/values/strings.xml` ships in the APK, so it's
reported like any other file. As shipped:

```toml
[allowlist]
description = "Binary resources, screenshot goldens and build outputs"
paths = [
    '''(^|/)src/[^/]+/res/(drawable|mipmap)[^/]*/[^/]+\.(png|webp|jpe?g|gif)$''',   # images
    '''(^|/)src/[^/]+/res/font[^/]*/[^/]+\.(ttf|otf)$''',                         # fonts
    '''(^|/)src/test/screenshots/.+\.png$''',                                     # Roborazzi goldens
    '''^([^/]+/){0,3}build/''',                                                   # build outputs (a module's build/)
    '''(^|/)gradle/wrapper/gradle-wrapper\.(jar|properties)$''',                  # Gradle wrapper
    '''\.lock$''',                                                                # lock files
]
regexes = [
    '''ANDROID_KEYSTORE_PASSWORD''',               # variable names in workflows/build files
    '''SENTRY_DSN''',                              # variable names
    '''GOOGLE_PLAY_SERVICE_ACCOUNT_JSON''',
]
```

A false positive in a text file is silenced on its line with a `gitleaks:allow` comment (`// gitleaks:allow`,
`<!-- gitleaks:allow -->`) or with a narrow path entry — never by allowlisting a whole directory such as `res/`.

The hook ships as `.android-forge-pre-commit.sh` (committed, so a fresh clone can reinstall it) and
`/android-forge-init` copies it to `.git/hooks/pre-commit` (executable):

```bash
#!/usr/bin/env bash
# Installed at .git/hooks/pre-commit by /android-forge-init.
# Set SKIP_GITLEAKS=1 to bypass for an emergency commit (rotate any leaked secret afterward).
set -euo pipefail

if [[ "${SKIP_GITLEAKS:-}" == "1" ]]; then
    exit 0
fi

if ! command -v gitleaks >/dev/null; then
    echo "warning: gitleaks not installed; install with: brew install gitleaks"
    echo "         skipping secret scan for this commit."
    exit 0
fi

gitleaks protect --staged --config .gitleaks.toml --no-banner --redact
```

Reinstall after a clone: `cp .android-forge-pre-commit.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit`.

## GitHub server-side scanning

Enable in repo Settings → Code security and analysis:

- ✅ **Secret scanning** — alerts on detected secrets in repo + history
- ✅ **Push protection** — blocks the push if a secret is detected at push time

These are free for public repos and included in GitHub Advanced Security for private repos.

## What to do when a secret leaks

1. **Rotate the secret immediately** at its source (regenerate API key, change password, generate new keystore).
2. Force-push history rewrite is *not* enough — GitHub keeps unreferenced commits accessible via the API for some time; rotation is the only real fix.
3. Audit access logs (Sentry, Firebase, Google Play Console) for unauthorized use during the exposure window.
4. Document the incident in `docs/DECISIONS/NNNN-secret-rotation.md` (date, secret type, scope, remediation).

## Don't put in CLAUDE.md or docs/

Per-project CLAUDE.md mentions *which* secrets exist (e.g. "Sentry DSN required") but never the secrets themselves. Docs reference secret *names* (`SENTRY_DSN`), never values.

## Data at rest

Secrets the **app** stores on the device (tokens, keys) go into a DataStore whose serializer encrypts with
**Tink** under an Android Keystore–backed key — never `EncryptedSharedPreferences` (all of
`androidx.security:security-crypto` is deprecated). Sign-in flows use Credential Manager; sensitive server
calls attach a Play Integrity token. The `android-permissions-security` and `android-intent-security`
skills audit the manifest and IPC surfaces.
