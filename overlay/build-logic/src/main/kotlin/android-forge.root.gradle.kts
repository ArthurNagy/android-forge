import com.android.build.api.artifact.ScopedArtifact
import com.android.build.api.variant.AndroidComponentsExtension
import com.android.build.api.variant.ScopedArtifacts
import org.gradle.testing.jacoco.plugins.JacocoTaskExtension

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
 * 3. Owns the coverage gate: `./gradlew coverageVerify` aggregates JaCoCo data from every Android
 *    library / application and Kotlin JVM module (not :core:testing, which only holds test doubles,
 *    nor `com.android.test` modules like :benchmarks) and fails below 85% line coverage;
 *    `./gradlew coverageReport` writes the HTML/XML report to build/reports/jacoco/coverageReport/.
 *    New modules are picked up automatically — nothing to register. Android classes come from AGP's
 *    public Variant API (ScopedArtifact.CLASSES of the debug variant); each module's `coverageInputs`
 *    task fails the gate when a module's classes or execution data go missing.
 *    android-forge projects have NO product flavors: the gate measures one debug variant per module,
 *    and its `coverageInputs` check fails, naming the variants, when a module declares flavors (the rest
 *    of the build keeps working; `unitTests` runs every debug variant's tests).
 * 4. Formats the root and settings scripts and build-logic itself (ktlint via Spotless); modules
 *    format their own sources through android-forge.spotless.
 */
plugins {
    base
    jacoco
    id("com.diffplug.spotless")
}

val catalog = extensions.getByType<VersionCatalogsExtension>().named("libs")

jacoco {
    toolVersion = catalog.findVersion("jacoco").get().requiredVersion
}

spotless {
    val ktlintVersion = catalog.findVersion("ktlint").get().requiredVersion
    kotlinGradle {
        target("*.gradle.kts", "build-logic/*.gradle.kts", "build-logic/src/**/*.gradle.kts")
        ktlint(ktlintVersion)
    }
    kotlin {
        target("build-logic/src/**/*.kt")
        ktlint(ktlintVersion)
    }
}

val unitTests = tasks.register("unitTests") {
    group = "verification"
    description = "Runs the local unit tests of every module (Android debug + JVM)."
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
    // Hilt/Dagger-generated Java (AGP's classes include javac output): never counted
    "**/Hilt_*",
    "**/*_Hilt*",
    "**/Dagger*",
    "**/*_Factory*",
    "**/*_MembersInjector*",
    "**/*Module_*",
    "**/*_GeneratedInjector*",
    "**/*_ComponentTreeDeps*",
    "hilt_aggregated_deps/**",
    "dagger/**",
    // Room's KSP-generated DAO/database implementations
    "**/*_Impl*",
    // Android-generated R and BuildConfig
    "**/R.class",
    "**/R\$*.class",
    "**/BuildConfig.*",
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

val coverageClasses = objects.fileCollection()
val coverageExecutionData = objects.fileCollection()
val coverageSources = objects.fileCollection()

fun registerCoverageInputs(
    module: Project,
    testTask: String,
    configure: CoverageInputs.() -> Unit,
): TaskProvider<CoverageInputs> {
    val inputs = module.tasks.register<CoverageInputs>("coverageInputs") {
        group = "verification"
        description = "Checks this module's classes and JaCoCo execution data for the root coverage gate."
        dependsOn(module.tasks.named { it == testTask }) // absent in a module with product flavors: the check says so
        modulePath = module.path
        sources.from(module.fileTree("src/main") { include("**/*.kt", "**/*.java") })
        tests.from(module.fileTree("src/test") { include("**/*.kt", "**/*.java") })
        executionData.from(
            module.provider {
                listOfNotNull(module.tasks.findByName(testTask)?.extensions?.findByType<JacocoTaskExtension>()?.destinationFile)
            },
        )
        configure()
    }
    val excludes = coverageExcludes
    coverageClasses.from(inputs.map { task -> task.classes.asFileTree.matching { exclude(excludes) } })
    coverageExecutionData.from(inputs.map { it.executionData })
    coverageSources.from(module.files("src/main/kotlin", "src/main/java"))
    return inputs
}

subprojects {
    val module = this
    listOf("com.android.library", "com.android.application").forEach { androidPlugin ->
        pluginManager.withPlugin(androidPlugin) {
            unitTests.configure { dependsOn(module.tasks.named { it.startsWith("test") && it.endsWith("DebugUnitTest") }) }
            if (module.path == ":core:testing") return@withPlugin
            val inputs = registerCoverageInputs(module, "testDebugUnitTest") { classes.from(classDirs) }
            val components = module.extensions.getByType(AndroidComponentsExtension::class.java)
            components.onVariants(components.selector().withBuildType("debug")) { variant ->
                if (variant.productFlavors.isNotEmpty()) {
                    inputs.configure { flavoredVariants.add(variant.name) }
                    return@onVariants
                }
                variant.artifacts
                    .forScope(ScopedArtifacts.Scope.PROJECT)
                    .use(inputs)
                    .toGet(ScopedArtifact.CLASSES, CoverageInputs::classJars, CoverageInputs::classDirs)
            }
        }
    }
    pluginManager.withPlugin("org.jetbrains.kotlin.jvm") {
        unitTests.configure { dependsOn("${module.path}:test") }
        if (module.path == ":core:testing") return@withPlugin
        val main = module.extensions.getByType<SourceSetContainer>().named("main")
        registerCoverageInputs(module, "test") { classes.from(main.map { it.output.classesDirs }) }
    }
}

val coverageAggregateInputs = tasks.register<CoverageAggregateInputs>("coverageAggregateInputs") {
    group = "verification"
    description = "Fails the coverage gate when it would measure nothing."
    classes.from(coverageClasses)
    executionData.from(coverageExecutionData)
}

fun JacocoReportBase.aggregateCoverage() {
    dependsOn(unitTests, coverageAggregateInputs)
    executionData.from(coverageExecutionData)
    classDirectories.from(coverageClasses)
    sourceDirectories.from(coverageSources)
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
    description = "Fails when aggregated line coverage drops below 85%."
    aggregateCoverage()
    violationRules {
        rule {
            limit {
                counter = "LINE"
                minimum = "0.85".toBigDecimal()
            }
        }
    }
}
