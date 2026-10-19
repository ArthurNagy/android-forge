---
description: Find an Android/Jetpack (or any Maven) library — Android docs + Google Maven + Maven Central — add it to gradle/libs.versions.toml and the right module, and install the matching Android skill tier when one exists.
argument-hint: <search-query or group:artifact>
---

# /android-forge-add-library

Library discovery for a pure-Android project. Jetpack and Google libraries come first (the stack rule: the
Android-first option wherever one exists); anything else comes from Maven Central.

## Arguments

- **`<search-query>`**: free-form (`"camera"`, `"background work"`, `"date picker"`), or exact coordinates
  (`androidx.camera:camera-compose`).

## Flow

### 1. Is it already decided?

Check `docs/stack.md` (plugin) for the concern first — networking, persistence, images, DI, logging, crash
reporting, background work, media, camera, security, form factors are already locked or have a documented opt-in.
If the query maps to one (e.g. "http client" → Retrofit + OkHttp in `:core:network`, "database" → Room 3 via the
`data-layer` skill's First table recipe, "wear app" → `/android-forge-add-form-factor wear`), say so and follow that
path instead of adding a competing library.

### 2. Discover candidates

```bash
android docs search "<query>"                    # official Jetpack/Google guidance; fetch the best hit:
android docs fetch kb://…                        # names the artifacts + current setup
```

- Jetpack groups: `curl -sf https://dl.google.com/dl/android/maven2/master-index.xml | grep -o '<[a-z0-9.]*' | grep -i "<keyword>"`
  then `…/<group/path>/group-index.xml` lists that group's artifacts.
- Anything else: Maven Central's search (`curl -s "https://search.maven.org/solrsearch/select?q=<keyword>&rows=10&wt=json"` —
  use it only to find coordinates; its version field lags, versions come from step 3).

Present up to 5 candidates with `AskUserQuestion` (coordinates, what it is, Jetpack/Google vs third-party, stable or
not). The user picks one.

### 3. Latest stable version

When Android Studio is running (`android studio check`), `android studio version-lookup <group>:<artifact>` gives the
current stable and preview versions. Otherwise — and always as the source of truth — read `maven-metadata.xml`,
sorted by version, purely numeric releases only:

```bash
GROUP="<group>"; ARTIFACT="<artifact>"; GROUP_PATH="${GROUP//.//}"
latest_stable() {  # $1 = repository base URL → newest purely numeric version, or ""
  curl -sfL "$1/${GROUP_PATH}/${ARTIFACT}/maven-metadata.xml" 2>/dev/null \
    | grep -oE '<version>[^<]+</version>' | sed 's/<[^>]*>//g' \
    | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V | tail -1
}
VERSION="$(latest_stable https://dl.google.com/dl/android/maven2)"
[ -n "${VERSION}" ] || VERSION="$(latest_stable https://repo1.maven.org/maven2)"
```

No stable release → list the newest pre-releases and ask whether to pin one (never silently). Pre-stable Jetpack
(XR, Glance Wear, AppFunctions) is normal for some form factors — pin the exact version the official docs name.

### 4. Catalog

Kebab-case library alias, camelCase version key, matching the catalog's style:

```bash
LIB_KEY="$(printf '%s' "${ARTIFACT}" | tr '[:upper:]' '[:lower:]' | tr '._' '--')"
grep -qE "^${LIB_KEY}[[:space:]]*=" gradle/libs.versions.toml \
  && LIB_KEY="$(printf '%s' "${GROUP##*.}" | tr '[:upper:]' '[:lower:]' | tr '._' '--')-${LIB_KEY}"
VERSION_KEY="$(printf '%s' "${LIB_KEY}" | awk -F- '{printf "%s", $1; for (i = 2; i <= NF; i++) printf "%s", toupper(substr($i, 1, 1)) substr($i, 2)}')"
```

Edit `gradle/libs.versions.toml`: `[versions] <VERSION_KEY> = "<VERSION>"` (reuse a sibling's `version.ref` for the same
library family; a Compose artifact covered by the BOM gets **no** version) and
`[libraries] <LIB_KEY> = { module = "<GROUP>:<ARTIFACT>", version.ref = "<VERSION_KEY>" }`. Avoid aliases whose first
segment is reserved (`versions`, `bundles`, `plugins`, …) or a segment starting with a digit.

A **Gradle plugin** (Firebase, gradle-play-publisher, Sentry) goes on build-logic's classpath instead: a `[libraries]`
entry for its plugin artifact, `implementation(libs.<alias>)` in `build-logic/build.gradle.kts`, then `id("<plugin id>")`
in the module — never `alias(libs.plugins.x)` (build-logic already put AGP & co. on the classpath).

### 5. Which module

`AskUserQuestion`, defaulting by layer: network/persistence → `:core:network` / `:core:database` / `:core:data` (never
a feature — features see only `:core:domain`); Compose UI components → the feature `impl` that uses it, or
`:core:designsystem` when shared; Android APIs a use case needs → behind a `:core:domain` interface implemented in
`:core:data`; a form-factor library → that form factor's module. Add `implementation(libs.<alias>)` in its
`dependencies { }`.

### 6. Matching Android skill

Install the capability tier when the library has one (`scripts/skills.sh tiers`):

| Library | Tier |
|---|---|
| `androidx.camera:*` | `camerax` |
| `androidx.appfunctions:*` | `appfunctions` |
| `com.google.mlkit:genai-*` | `genai` |
| `com.google.ai.edge.litert:*` | `litert` |
| `androidx.credentials:*` | `credentials` |
| `com.android.billingclient:*` | `billing` |
| `com.google.android.engage:*` | `engage` |
| `androidx.media3:media3-cast` | `cast` |
| `androidx.glance:glance-appwidget` | `widgets` |

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skills.sh" install "<project-root>" <tier>
```

### 7. Verify

`./gradlew :<module>:assembleDebug lint` — a new library can bring Lint findings (permissions, manifest merges).
A library that adds permissions or exported components: run the reviewer's security pass
(`android-permissions-security` skill).

### 8. ADR

A library that changes architecture or adds a paradigm → suggest `docs/DECISIONS/NNNN-add-<lib>.md` (`adr-authoring`).

### 9. Report

```
✓ Added <group>:<artifact>:<version>  (<Jetpack/Google | third-party>)
✓ Catalog: versions.<VERSION_KEY> + libraries.<LIB_KEY>
✓ Used in: <module>/build.gradle.kts
✓ Android skill: <tier installed | none>
✓ Build + lint: green | red
```
