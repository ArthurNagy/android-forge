/*
 * Room 3 (androidx.room3, KSP-only, coroutines-first) for :core:database. Schemas are exported to
 * <module>/schemas (commit them: they are the migration history); the bundled SQLite driver gives
 * every Android version the same SQLite. Local tests run DAOs under Robolectric on the framework
 * driver (AndroidSQLiteDriver) — the bundled driver has no host-JVM native library there.
 */
plugins {
    id("com.google.devtools.ksp")
    id("androidx.room3")
}

val catalog = extensions.getByType<VersionCatalogsExtension>().named("libs")

fun lib(alias: String) = catalog.findLibrary(alias).get()

room3 {
    schemaDirectory("$projectDir/schemas")
}

dependencies {
    "implementation"(lib("room3-runtime"))
    "implementation"(lib("androidx-sqlite-bundled"))
    "ksp"(lib("room3-compiler"))
    "testImplementation"(lib("room3-testing"))
    "testImplementation"(lib("androidx-sqlite-framework"))
    "testImplementation"(lib("robolectric"))
    "testImplementation"(lib("androidx-test-core"))
    "testImplementation"(lib("androidx-test-ext-junit"))
}
