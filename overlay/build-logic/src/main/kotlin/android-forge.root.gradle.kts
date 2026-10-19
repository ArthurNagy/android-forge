/*
 * Convention for the ROOT project — applied as `id("android-forge.root")` in the root
 * build.gradle.kts (init/adopt write it).
 *
 * 1. Loads build-logic — and the AGP / Kotlin / Hilt / KSP / Spotless / Roborazzi plugins it
 *    bundles — once, in the root classloader. Modules then apply plugins by id with no version
 *    (never `alias(libs.plugins.x)` in a module or the root: the plugin is already on the
 *    classpath). Without the single classloader Spotless 8's shared build service fails.
 * 2. `./gradlew unitTests` runs every module's local tests (debug unit tests of Android modules,
 *    `test` of JVM modules) — `testDebugUnitTest` alone would skip the JVM modules.
 * 3. Owns the coverage gate: `./gradlew coverageVerify` aggregates JaCoCo data from every module
 *    (except :core:testing, which only holds test doubles) and fails below 75% line coverage;
 *    `./gradlew coverageReport` writes the HTML/XML report to build/reports/jacoco/coverageReport/.
 *    New modules are picked up automatically — nothing to register.
 */
plugins {
    base
    jacoco
}

val catalog = extensions.getByType<VersionCatalogsExtension>().named("libs")

jacoco {
    toolVersion = catalog.findVersion("jacoco").get().requiredVersion
}

val unitTests = tasks.register("unitTests") {
    group = "verification"
    description = "Runs the local unit tests of every module (Android debug + JVM)."
}

subprojects {
    val projectPath = path
    listOf("com.android.library", "com.android.application").forEach { androidPlugin ->
        pluginManager.withPlugin(androidPlugin) {
            unitTests.configure { dependsOn("$projectPath:testDebugUnitTest") }
        }
    }
    pluginManager.withPlugin("org.jetbrains.kotlin.jvm") {
        unitTests.configure { dependsOn("$projectPath:test") }
    }
}

// Generated or wiring-only code: nothing to assert on, and covered by building the app.
val coverageExcludes = listOf(
    // Compose compiler singletons, kotlinx-serialization serializers
    "**/ComposableSingletons*",
    "**/*\$\$serializer*",
    // Hilt modules (@Module objects/interfaces) and the app's framework entry points
    "**/*Module.class",
    "**/*Module\$*.class",
    "**/MainApplication*",
    "**/MainActivity.class",
    "**/MainActivity\$*",
    // :feature:*:api modules hold only Nav 3 keys; a feature's entry builders only map keys to screens
    "**/feature/*/api/**",
    "**/*EntriesKt*",
    // DomainError value types (no logic; exercised wherever the code returning them is tested)
    "**/core/domain/DomainError*",
    // design tokens
    "**/core/designsystem/AppColorsKt*",
    "**/core/designsystem/AppDimens*",
    "**/core/designsystem/AppSpacing*",
    "**/core/designsystem/AppType*",
    // production dispatchers (one-liners over Dispatchers.*)
    "**/RealDispatcherProvider*",
)

val coveredProjects = subprojects.filter { it.path != ":core:testing" }

fun JacocoReportBase.aggregateCoverage() {
    dependsOn(unitTests)
    executionData.from(
        coveredProjects.map { p ->
            p.fileTree(p.layout.buildDirectory) {
                include("outputs/unit_test_code_coverage/debugUnitTest/*.exec", "jacoco/test.exec")
            }
        },
    )
    classDirectories.from(
        coveredProjects.map { p ->
            p.fileTree(p.layout.buildDirectory) {
                // Kotlin output only: Hilt/Dagger generate Java, which this leaves out on purpose.
                include(
                    "intermediates/built_in_kotlinc/debug/compileDebugKotlin/classes/**",
                    "classes/kotlin/main/**",
                )
                exclude(coverageExcludes)
            }
        },
    )
    sourceDirectories.from(coveredProjects.map { it.file("src/main/kotlin") })
}

tasks.register<JacocoReport>("coverageReport") {
    group = "verification"
    description = "Aggregated JaCoCo coverage report of every module's unit tests."
    aggregateCoverage()
    reports {
        xml.required = true
        html.required = true
    }
}

tasks.register<JacocoCoverageVerification>("coverageVerify") {
    group = "verification"
    description = "Fails when aggregated line coverage drops below 75%."
    aggregateCoverage()
    violationRules {
        rule {
            limit {
                counter = "LINE"
                minimum = "0.75".toBigDecimal()
            }
        }
    }
}
