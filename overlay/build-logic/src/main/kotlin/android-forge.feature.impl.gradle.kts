/*
 * A feature's `impl` module (:feature:<name>:impl): internal screens, Orbit ViewModels and state,
 * strings, and the Hilt @IntoSet entry builder that contributes its Nav 3 entries to the app.
 *
 * Wires the dependencies every feature may use. A feature never depends on :core:data or another
 * feature's impl — only on other features' :api modules (add those in the module itself).
 */
plugins {
    id("android-forge.android.library.compose")
    id("android-forge.hilt")
}

val catalog = extensions.getByType<VersionCatalogsExtension>().named("libs")

fun lib(alias: String) = catalog.findLibrary(alias).get()

dependencies {
    "implementation"(project(":core:model"))
    "implementation"(project(":core:domain"))
    "implementation"(project(":core:designsystem"))
    "implementation"(project(":core:ui"))
    "implementation"(project(":core:navigation"))

    "implementation"(lib("orbit-viewmodel"))
    "implementation"(lib("orbit-compose"))
    "implementation"(lib("androidx-hilt-lifecycle-viewmodel-compose"))
    "implementation"(lib("androidx-lifecycle-runtime-compose"))
    "implementation"(lib("androidx-navigation3-runtime"))
    "implementation"(lib("androidx-compose-material3-adaptive-navigation3"))
    "implementation"(lib("timber"))

    "testImplementation"(lib("orbit-test"))
    "testImplementation"(lib("turbine"))
}
