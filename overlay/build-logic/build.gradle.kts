plugins {
    `kotlin-dsl`
}

dependencies {
    implementation(libs.android.gradle.plugin)
    implementation(libs.kotlin.gradle.plugin)
    implementation(libs.compose.compiler.gradle.plugin)
    implementation(libs.kotlin.serialization.gradle.plugin)
    implementation(libs.ksp.gradle.plugin)
    implementation(libs.hilt.gradle.plugin)
    implementation(libs.spotless.gradle.plugin)
    implementation(libs.roborazzi.gradle.plugin)
    implementation(libs.room3.gradle.plugin)
    implementation(libs.baselineprofile.gradle.plugin)
}

// Convention plugins are PRECOMPILED SCRIPT PLUGINS in src/main/kotlin/*.gradle.kts — the
// `kotlin-dsl` plugin registers each by filename (android-forge.android.library.gradle.kts →
// id "android-forge.android.library"). No manual gradlePlugin {} registration needed.
