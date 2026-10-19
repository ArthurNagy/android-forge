/*
 * A feature's `api` module (:feature:<name>:api): its Navigation 3 keys and nothing else. Pure
 * Kotlin, so another feature's `impl` can depend on it to navigate here without pulling in this
 * feature's screens (Nav 3 modularization guide).
 */
plugins {
    id("android-forge.jvm.library")
    id("org.jetbrains.kotlin.plugin.serialization")
}

val catalog = extensions.getByType<VersionCatalogsExtension>().named("libs")

dependencies {
    "api"(catalog.findLibrary("androidx-navigation3-runtime").get())
    "implementation"(catalog.findLibrary("kotlinx-serialization-core").get())
}
