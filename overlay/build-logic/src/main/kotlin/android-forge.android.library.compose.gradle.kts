/*
 * Android library + Jetpack Compose (Compose BOM, Material 3, tooling) + the screen-test stack:
 * Robolectric, Compose UI Test and Roborazzi screenshot tests, all as local unit tests
 * (`./gradlew testDebugUnitTest`; record goldens with `recordRoborazziDebug`, CI verifies them).
 * Slack's compose-lints add Compose checks to Android Lint (warnings are errors here too).
 */
plugins {
    id("android-forge.android.library")
    id("org.jetbrains.kotlin.plugin.compose")
    id("io.github.takahirom.roborazzi")
}

val catalog = extensions.getByType<VersionCatalogsExtension>().named("libs")

fun lib(alias: String) = catalog.findLibrary(alias).get()

android {
    buildFeatures {
        compose = true
    }
}

// Screenshot goldens are committed next to the tests: `./gradlew recordRoborazziDebug` writes them,
// CI verifies against them (`-Proborazzi.test.verify=true`).
roborazzi {
    outputDir = layout.projectDirectory.dir("src/test/screenshots")
}

dependencies {
    val composeBom = platform(lib("androidx-compose-bom"))
    "implementation"(composeBom)
    "testImplementation"(composeBom)
    "androidTestImplementation"(composeBom)

    "implementation"(lib("androidx-compose-ui"))
    "implementation"(lib("androidx-compose-foundation"))
    "implementation"(lib("androidx-compose-material3"))
    "implementation"(lib("androidx-compose-ui-tooling-preview"))
    "debugImplementation"(lib("androidx-compose-ui-tooling"))
    "debugImplementation"(lib("androidx-compose-ui-test-manifest"))
    "lintChecks"(lib("compose-lint-checks"))

    "testImplementation"(lib("robolectric"))
    "testImplementation"(lib("androidx-test-ext-junit"))
    "testImplementation"(lib("androidx-compose-ui-test-junit4"))
    "testImplementation"(lib("roborazzi"))
    "testImplementation"(lib("roborazzi-compose"))
}
