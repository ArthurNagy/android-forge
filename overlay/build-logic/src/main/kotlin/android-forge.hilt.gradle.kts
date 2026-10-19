/*
 * Hilt (Dagger) on KSP for an Android module: applied after an android-forge Android convention.
 * Constructor injection everywhere; @AndroidEntryPoint only on framework entry points
 * (Activity, Service, BroadcastReceiver). See ADR 0002.
 */
plugins {
    id("com.google.devtools.ksp")
    id("com.google.dagger.hilt.android")
}

val catalog = extensions.getByType<VersionCatalogsExtension>().named("libs")

dependencies {
    "implementation"(catalog.findLibrary("hilt-android").get())
    "ksp"(catalog.findLibrary("hilt-compiler").get())
}
