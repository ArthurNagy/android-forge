import org.gradle.api.GradleException
import org.gradle.api.artifacts.VersionCatalog

/**
 * The catalog's `androidMinSdk`, checked against android-forge's floor: `java.time` (used by the
 * pure-Kotlin :core modules) needs API 26 without core-library desugaring, which android-forge doesn't
 * configure. Fails at configuration rather than crashing on old devices at runtime.
 */
internal fun VersionCatalog.androidMinSdk(): Int {
    val value = findVersion("androidMinSdk").get().requiredVersion
    val minSdk = value.toIntOrNull()
    if (minSdk == null || minSdk < MIN_SDK_FLOOR) {
        throw GradleException(
            "androidMinSdk = \"$value\" in gradle/libs.versions.toml: android-forge needs minSdk $MIN_SDK_FLOOR or " +
                "higher (java.time without core-library desugaring). New projects use 29.",
        )
    }
    return minSdk
}

private const val MIN_SDK_FLOOR = 26
