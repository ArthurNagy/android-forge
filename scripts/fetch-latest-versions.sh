#!/usr/bin/env bash
#
# Query Google Maven and Maven Central for the latest versions of every
# locked-stack library. Prints a TOML-like report; does NOT modify any file.
#
# Used by /android-forge-bump-stack — the slash command parses this output, diffs
# against the project's libs.versions.toml, and proposes an updated catalog
# in a single commit. When Android Studio is running, the command cross-checks
# with `android studio version-lookup`; this script is the offline-safe source.
#
# Every emitted key is the [versions] key an android-forge project actually uses:
# the toolchain keys come from `android create`'s generated catalog
# (androidGradlePlugin, kotlin, androidxComposeBom, androidxLifecycle, nav3Core, …),
# the rest from overlay/gradle/libs.versions.toml.additions.tmpl.
#
# Usage:
#   fetch-latest-versions.sh [json|toml]    (default: toml)

set -euo pipefail

fmt="${1:-toml}"

# coord: group:artifact:version-key:repo:channel
#   channel "stable" — newest purely numeric version (1.2.3, 2026.09.00); any qualifier
#                      (-alpha01, -rc01, -beta1, ...) is skipped.
#   channel "pre"    — the pin itself tracks a pre-release line (XR, Glance Wear, …); report
#                      the newest pre-release unless a stable release at or above its base exists.
declare -a coords=(
    # --- toolchain (keys owned by `android create`'s catalog) ---
    "com.android.tools.build:gradle:androidGradlePlugin:google-maven:stable"
    "org.jetbrains.kotlin:kotlin-stdlib:kotlin:maven-central:stable"
    "com.google.devtools.ksp:symbol-processing-gradle-plugin:ksp:maven-central:stable"
    "androidx.compose:compose-bom:androidxComposeBom:google-maven:stable"
    "androidx.core:core-ktx:androidxCore:google-maven:stable"
    "androidx.activity:activity-compose:androidxActivity:google-maven:stable"
    "androidx.lifecycle:lifecycle-runtime-compose:androidxLifecycle:google-maven:stable"
    "androidx.lifecycle:lifecycle-viewmodel-navigation3:lifecycleViewmodelNav3:google-maven:stable"
    "androidx.navigation3:navigation3-ui:nav3Core:google-maven:stable"
    "org.jetbrains.kotlinx:kotlinx-coroutines-core:coroutines:maven-central:stable"
    "androidx.test:core:androidxTest:google-maven:stable"
    "androidx.test.ext:junit:androidxTestExt:google-maven:stable"
    "androidx.test:runner:androidxTestRunner:google-maven:stable"
    "androidx.test.espresso:espresso-core:androidxTestEspresso:google-maven:stable"
    "junit:junit:junit:maven-central:stable"
    # --- locked stack (keys owned by the overlay additions) ---
    "androidx.compose.material3.adaptive:adaptive-navigation3:material3Adaptive:google-maven:stable"
    "com.google.dagger:hilt-android:hilt:maven-central:stable"
    "androidx.hilt:hilt-lifecycle-viewmodel-compose:androidxHilt:google-maven:stable"
    "org.orbit-mvi:orbit-viewmodel:orbitMvi:maven-central:stable"
    "com.michael-bull.kotlin-result:kotlin-result:kotlinResult:maven-central:stable"
    "org.jetbrains.kotlinx:kotlinx-serialization-json:kotlinxSerialization:maven-central:stable"
    "androidx.datastore:datastore-preferences:androidxDatastore:google-maven:stable"
    "io.coil-kt.coil3:coil-compose:coil:maven-central:stable"
    "com.jakewharton.timber:timber:timber:maven-central:stable"
    "app.cash.turbine:turbine:turbine:maven-central:stable"
    "org.robolectric:robolectric:robolectric:maven-central:stable"
    "com.google.truth:truth:truth:maven-central:stable"
    "io.github.takahirom.roborazzi:roborazzi:roborazzi:maven-central:stable"
    # --- opt-ins (present only when the project selected them; bump-stack ignores absent keys) ---
    "com.squareup.retrofit2:retrofit:retrofit:maven-central:stable"
    "com.squareup.okhttp3:okhttp:okhttp:maven-central:stable"
    "androidx.room3:room3-runtime:room3:google-maven:stable"
    "androidx.sqlite:sqlite-bundled:androidxSqlite:google-maven:stable"
    "androidx.work:work-runtime-ktx:androidxWork:google-maven:stable"
    "androidx.benchmark:benchmark-macro-junit4:androidxBenchmark:google-maven:stable"
    "androidx.baselineprofile:androidx.baselineprofile.gradle.plugin:androidxBaselineProfile:google-maven:stable"
    "androidx.profileinstaller:profileinstaller:androidxProfileInstaller:google-maven:stable"
    "androidx.test.uiautomator:uiautomator:androidxUiAutomator:google-maven:stable"
    "com.google.firebase:firebase-bom:firebaseBom:google-maven:stable"
    "com.google.gms:google-services:googleServices:google-maven:stable"
    "com.google.firebase:firebase-crashlytics-gradle:firebaseCrashlyticsPlugin:google-maven:stable"
    "com.google.firebase:firebase-appdistribution-gradle:firebaseAppDistributionPlugin:google-maven:stable"
    "io.sentry:sentry-android:sentry:maven-central:stable"
    "com.github.triplet.gradle:play-publisher:playPublisher:maven-central:stable"
    # --- form factors (opt-in; pre-stable lines tracked on the "pre" channel) ---
    "androidx.car.app:app:androidxCarApp:google-maven:stable"
    "androidx.tv:tv-material:androidxTvMaterial:google-maven:stable"
    "androidx.wear.compose:compose-material3:wearCompose:google-maven:stable"
    "androidx.wear.tiles:tiles:wearTiles:google-maven:stable"
    "androidx.wear.protolayout:protolayout:wearProtolayout:google-maven:stable"
    "com.google.android.gms:play-services-wearable:playServicesWearable:google-maven:stable"
    "androidx.glance:glance-appwidget:androidxGlance:google-maven:stable"
    "androidx.media3:media3-exoplayer:media3:google-maven:stable"
    "androidx.xr.compose:compose:xrCompose:google-maven:pre"
    "androidx.xr.scenecore:scenecore:xrScenecore:google-maven:pre"
    "androidx.xr.glimmer:glimmer:xrGlimmer:google-maven:pre"
    "androidx.xr.projected:projected:xrProjected:google-maven:pre"
    # --- quality gates ---
    "com.diffplug.spotless:spotless-plugin-gradle:spotless:maven-central:stable"
    "com.pinterest.ktlint:ktlint-cli:ktlint:maven-central:stable"
    "io.nlopez.compose.rules:ktlint:composeRules:maven-central:stable"
    "org.jacoco:org.jacoco.core:jacoco:maven-central:stable"
)

# Authoritative maven-metadata.xml is the source of truth for both repos.
repo_base() {
    case "$1" in
        maven-central) echo "https://repo1.maven.org/maven2" ;;
        google-maven)  echo "https://dl.google.com/dl/android/maven2" ;;
    esac
}

# All published versions, one per line, in version order (oldest first).
# <versions> in maven-metadata.xml is deploy order, NOT version order — a patch deployed after
# a newer beta would otherwise read as "latest". `sort -V` exists in GNU coreutils and stock macOS.
list_versions() {
    local repo="$1" group="$2" artifact="$3"
    curl -sfL "$(repo_base "$repo")/${group//.//}/${artifact}/maven-metadata.xml" 2>/dev/null \
        | grep -oE '<version>[^<]+</version>' | sed 's/<[^>]*>//g' | sort -V || true
}

# Version-order comparison: true if $1 >= $2.
version_ge() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]; }

# Latest stable Gradle release (the wrapper isn't a catalog key — emitted in its own section).
fetch_gradle() {
    curl -sfL https://services.gradle.org/versions/current 2>/dev/null \
        | grep -oE '"version" *: *"[0-9][^"]*"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/' || true
}

fetch_latest() {
    local repo="$1" group="$2" artifact="$3" channel="$4"
    local versions stable pre
    versions="$(list_versions "$repo" "$group" "$artifact")"
    stable="$(grep -E '^[0-9]+(\.[0-9]+)*$' <<< "$versions" | tail -1 || true)"
    case "$channel" in
        stable)
            echo "$stable"
            ;;
        pre)
            pre="$(grep -vE '^[0-9]+(\.[0-9]+)*$|SNAPSHOT' <<< "$versions" | tail -1 || true)"
            if [[ -z "$pre" ]] || { [[ -n "$stable" ]] && version_ge "$stable" "${pre%%-*}"; }; then
                echo "$stable"
            else
                echo "$pre"
            fi
            ;;
    esac
}

emit_toml() {
    echo "# android-forge fetch-latest-versions: $(date -u +%FT%TZ)"
    echo "[versions]"
    for entry in "${coords[@]}"; do
        IFS=':' read -r g a key repo channel <<< "$entry"
        local v
        v="$(fetch_latest "$repo" "$g" "$a" "$channel")"
        if [[ -z "$v" ]]; then
            echo "# WARN $key ($g:$a) — not found"
        else
            echo "$key = \"$v\""
        fi
    done
    echo
    echo "[wrapper]"
    local g; g="$(fetch_gradle)"
    if [[ -n "$g" ]]; then echo "gradle = \"$g\""; else echo "# WARN gradle — services.gradle.org unreachable"; fi
}

emit_json() {
    echo "{"
    local first=1
    for entry in "${coords[@]}"; do
        IFS=':' read -r g a key repo channel <<< "$entry"
        local v
        v="$(fetch_latest "$repo" "$g" "$a" "$channel")"
        [[ $first -eq 1 ]] || echo ","
        first=0
        printf '  "%s": "%s"' "$key" "$v"
    done
    printf ',\n  "gradle-wrapper": "%s"' "$(fetch_gradle)"
    echo
    echo "}"
}

case "$fmt" in
    toml) emit_toml ;;
    json) emit_json ;;
    *) echo "usage: $0 [json|toml]" >&2; exit 1 ;;
esac
