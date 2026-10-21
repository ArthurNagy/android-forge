/*
 * Pure-Kotlin JVM module (:core:model, :core:domain, :core:testing, :feature:*:api) — Google's
 * modularization guide: prefer Kotlin modules wherever no Android API is needed (faster builds,
 * nothing Android leaks in). Android Lint still runs over it (com.android.lint).
 */
plugins {
    id("org.jetbrains.kotlin.jvm")
    id("com.android.lint")
    id("android-forge.spotless")
    jacoco
}

val catalog = extensions.getByType<VersionCatalogsExtension>().named("libs")

fun catalogVersion(key: String): String = catalog.findVersion(key).get().requiredVersion

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

jacoco {
    toolVersion = catalogVersion("jacoco")
}

lint {
    warningsAsErrors = true
    abortOnError = true
    disable += listOf("GradleDependency", "NewerVersionAvailable", "AndroidGradlePluginVersion")
}

tasks.withType<Test>().configureEach {
    failOnNoDiscoveredTests = false
}

dependencies {
    "testImplementation"(catalog.findLibrary("junit").get())
    "testImplementation"(catalog.findLibrary("kotlin-test-junit").get())
    "testImplementation"(catalog.findLibrary("kotlinx-coroutines-test").get())
}
