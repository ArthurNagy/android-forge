import org.gradle.testing.jacoco.plugins.JacocoTaskExtension

/*
 * Convention for every app module (:app and the opt-in form-factor apps: :wear, :tv,
 * :automotive). Always Compose. Release builds run R8 (full mode is AGP's default) with
 * resource shrinking; `generateLocaleConfig` publishes the app's languages to the system's
 * per-app language settings (needs src/main/res/resources.properties).
 */
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    // Nav 3 keys declared in the app (the Home placeholder) must be @Serializable for back-stack saving.
    id("org.jetbrains.kotlin.plugin.serialization")
    id("io.github.takahirom.roborazzi")
    id("android-forge.spotless")
    jacoco
}

val catalog = extensions.getByType<VersionCatalogsExtension>().named("libs")

fun catalogVersion(key: String): String = catalog.findVersion(key).get().requiredVersion

fun lib(alias: String) = catalog.findLibrary(alias).get()

android {
    compileSdk = catalogVersion("androidCompileSdk").toInt()
    defaultConfig {
        minSdk = catalogVersion("androidMinSdk").toInt()
        targetSdk = catalogVersion("androidTargetSdk").toInt()
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    buildTypes {
        debug {
            enableUnitTestCoverage = true
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    androidResources {
        generateLocaleConfig = true
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
    failOnNoDiscoveredTests = false
    extensions.configure<JacocoTaskExtension> {
        isIncludeNoLocationClasses = true
        excludes = listOf("jdk.internal.*")
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

    "implementation"(lib("androidx-core-ktx"))
    "implementation"(lib("androidx-activity-compose"))
    "implementation"(lib("androidx-compose-ui"))
    "implementation"(lib("androidx-compose-foundation"))
    "implementation"(lib("androidx-compose-material3"))
    "implementation"(lib("androidx-compose-ui-tooling-preview"))
    "debugImplementation"(lib("androidx-compose-ui-tooling"))
    "debugImplementation"(lib("androidx-compose-ui-test-manifest"))

    // Shared doubles + robolectric.properties (the Robolectric SDK pin) on every module's local tests.
    "testImplementation"(project(":core:testing"))
    "testImplementation"(lib("junit"))
    "testImplementation"(lib("kotlin-test-junit"))
    "testImplementation"(lib("kotlinx-coroutines-test"))
    "testImplementation"(lib("robolectric"))
    "testImplementation"(lib("androidx-test-ext-junit"))
    "testImplementation"(lib("androidx-compose-ui-test-junit4"))
    "testImplementation"(lib("roborazzi"))
    "testImplementation"(lib("roborazzi-compose"))

    "androidTestImplementation"(lib("androidx-test-ext-junit"))
    "androidTestImplementation"(lib("androidx-test-runner"))
    "androidTestImplementation"(lib("androidx-compose-ui-test-junit4"))
}
