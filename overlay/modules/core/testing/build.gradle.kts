/*
 * :core:testing — shared test doubles (TestDispatcherProvider, MainDispatcherRule, fakes of
 * :core:domain interfaces used by more than one module), the Robolectric SDK pin
 * (robolectric.properties) and the Roborazzi screenshot tolerance (ScreenshotTolerancePlugin). Only
 * ever a `testImplementation` / `androidTestImplementation` dependency, never `implementation`.
 * Excluded from the coverage gate.
 */
plugins {
    id("android-forge.jvm.library")
}

dependencies {
    api(project(":core:domain"))
    api(libs.kotlinx.coroutines.test)
    api(libs.junit)
    api(libs.turbine)
    // The screenshot-tolerance plugin compiles against these; Android modules' tests bring them at runtime.
    compileOnly(libs.robolectric.pluginapi)
    compileOnly(libs.roborazzi.core)
}
