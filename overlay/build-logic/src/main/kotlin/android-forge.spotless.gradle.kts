/*
 * Formatting gate (`./gradlew spotlessCheck` / `spotlessApply`), applied by every android-forge
 * module convention: ktlint over Kotlin sources and build scripts, plus the compose-rules ktlint
 * ruleset (mrmans0n/compose-rules) over Kotlin sources. Rule tweaks live in the root .editorconfig.
 *
 * Versions come from the catalog's `ktlint` / `composeRules` keys so /android-forge-bump-stack
 * bumps them (type-safe `libs` accessors aren't generated inside precompiled script plugins).
 */
plugins {
    id("com.diffplug.spotless")
}

val catalog = extensions.getByType<VersionCatalogsExtension>().named("libs")
val ktlintVersion = catalog.findVersion("ktlint").get().requiredVersion
val composeRules = "io.nlopez.compose.rules:ktlint:" + catalog.findVersion("composeRules").get().requiredVersion

spotless {
    kotlin {
        target("src/**/*.kt")
        ktlint(ktlintVersion).customRuleSets(listOf(composeRules))
    }
    kotlinGradle {
        target("*.gradle.kts")
        ktlint(ktlintVersion)
    }
}
