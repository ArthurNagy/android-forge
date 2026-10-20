import org.gradle.testing.jacoco.plugins.JacocoTaskExtension

/*
 * Base convention for every Android library module (:core:* Android modules, :feature:*:impl,
 * form-factor libraries). SDK levels come from the catalog (`androidCompileSdk`, `androidMinSdk` — 26
 * at least: java.time without core-library desugaring),
 * Kotlin is AGP 9's built-in Kotlin (no kotlin-android plugin), debug unit tests record JaCoCo
 * coverage for the root `coverageVerify` gate, and Android Lint treats warnings as errors.
 *
 * Compose modules apply android-forge.android.library.compose on top of this.
 */
plugins {
    id("com.android.library")
    id("android-forge.spotless")
    jacoco
}

val catalog = extensions.getByType<VersionCatalogsExtension>().named("libs")

fun catalogVersion(key: String): String = catalog.findVersion(key).get().requiredVersion

android {
    compileSdk = catalogVersion("androidCompileSdk").toInt()
    defaultConfig {
        minSdk = catalog.androidMinSdk() // fails below android-forge's floor (26)
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildTypes {
        debug {
            enableUnitTestCoverage = true
        }
    }
    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
    testCoverage {
        jacocoVersion = catalogVersion("jacoco")
    }
    lint {
        warningsAsErrors = true
        abortOnError = true
        // Dependency freshness is /android-forge-bump-stack's job, not a lint failure.
        disable += listOf("GradleDependency", "NewerVersionAvailable", "AndroidGradlePluginVersion")
    }
}

jacoco {
    toolVersion = catalogVersion("jacoco")
}

// Local tests run on a JDK 21 toolchain whatever JDK runs Gradle: Robolectric's SDK 35+ runtimes need
// JDK 21 and fail on newer JDKs (module access to jdk.internal). Gradle provisions it via foojay.
val testLauncher = extensions.getByType<JavaToolchainService>().launcherFor { languageVersion = JavaLanguageVersion.of(21) }

tasks.withType<Test>().configureEach {
    javaLauncher = testLauncher
    // Robolectric's FileDescriptor interceptor (SDK 36+ app setup) reflects into jdk.internal.access.
    jvmArgs("--add-exports=java.base/jdk.internal.access=ALL-UNNAMED", "--add-opens=java.base/java.io=ALL-UNNAMED")
    // Gradle 9 fails a test task that has test sources but discovers no @Test; a fresh module
    // may only hold test helpers.
    failOnNoDiscoveredTests = false
    // Robolectric loads classes through its own class loader: without these, JaCoCo misses them.
    extensions.configure<JacocoTaskExtension> {
        isIncludeNoLocationClasses = true
        excludes = listOf("jdk.internal.*")
    }
}

dependencies {
    // Shared doubles + robolectric.properties (the Robolectric SDK pin) on every module's local tests.
    "testImplementation"(project(":core:testing"))
    "testImplementation"(catalog.findLibrary("junit").get())
    "testImplementation"(catalog.findLibrary("kotlin-test-junit").get())
    "testImplementation"(catalog.findLibrary("kotlinx-coroutines-test").get())
}
