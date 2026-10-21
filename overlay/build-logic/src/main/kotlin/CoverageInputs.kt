import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.Directory
import org.gradle.api.file.RegularFile
import org.gradle.api.provider.ListProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction

/**
 * One module's inputs to the root coverage gate (android-forge.root): its compiled classes — for an
 * Android module, the class directories of AGP's public `ScopedArtifact.CLASSES` ([classDirs]; its
 * [classJars] hold only R classes today and aren't measured); for a JVM module, the main source set's
 * output — and the JaCoCo execution data its unit tests wrote.
 *
 * Fails when either went missing, so a moved build directory or a disabled coverage flag fails the
 * gate instead of silently measuring less.
 */
abstract class CoverageInputs : DefaultTask() {
    @get:Input
    abstract val modulePath: Property<String>

    /** Debug variants with product flavors — the gate measures one debug variant per module, so it fails on them. */
    @get:Input
    abstract val flavoredVariants: ListProperty<String>

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val classJars: ListProperty<RegularFile>

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val classDirs: ListProperty<Directory>

    /** The module's measured class files (before the gate's exclusions). */
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val classes: ConfigurableFileCollection

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val executionData: ConfigurableFileCollection

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val sources: ConfigurableFileCollection

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val tests: ConfigurableFileCollection

    init {
        flavoredVariants.convention(emptyList())
        classJars.convention(emptyList())
        classDirs.convention(emptyList())
    }

    @TaskAction
    fun check() {
        val module = modulePath.get()
        if (flavoredVariants.get().isNotEmpty()) {
            throw GradleException(
                "Coverage gate: $module declares product flavors (${flavoredVariants.get().joinToString()}). android-forge " +
                    "measures one debug variant per module (coverageVerify, CI) — move per-environment values to build types.",
            )
        }
        val hasClasses = !classes.asFileTree.matching { include("**/*.class") }.isEmpty
        if (!sources.isEmpty && !hasClasses) {
            throw GradleException(
                "Coverage gate: $module has main sources but contributed no compiled classes " +
                    "(${classes.files.joinToString()}) — its code would silently drop out of coverageVerify. " +
                    "Check android-forge.root's class inputs against the current AGP / Kotlin plugin.",
            )
        }
        if (!tests.isEmpty && executionData.none { it.isFile }) {
            throw GradleException(
                "Coverage gate: $module has unit tests but they wrote no JaCoCo execution data " +
                    "(expected ${executionData.files.joinToString()}). Is JaCoCo still on for its unit tests? " +
                    "(Android modules: `enableUnitTestCoverage = true` on the debug build type — the android-forge conventions set it.)",
            )
        }
    }
}

/** Fails the gate when the aggregated inputs are empty: JaCoCo would skip the check or pass on NaN. */
abstract class CoverageAggregateInputs : DefaultTask() {
    /** Every covered module's classes after the gate's exclusions. */
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val classes: ConfigurableFileCollection

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val executionData: ConfigurableFileCollection

    @TaskAction
    fun check() {
        if (classes.asFileTree.matching { include("**/*.class") }.isEmpty) {
            throw GradleException("Coverage gate: no classes to measure — no covered module contributed any.")
        }
        if (executionData.none { it.isFile }) {
            throw GradleException("Coverage gate: no JaCoCo execution data — no module's unit tests ran with coverage.")
        }
    }
}
