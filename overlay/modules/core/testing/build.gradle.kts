/*
 * :core:testing — shared test doubles (TestDispatcherProvider, MainDispatcherRule, fakes of
 * :core:domain interfaces used by more than one module). Only ever a `testImplementation` /
 * `androidTestImplementation` dependency, never `implementation`. Excluded from the coverage gate.
 */
plugins {
    id("android-forge.jvm.library")
}

dependencies {
    api(project(":core:domain"))
    api(libs.kotlinx.coroutines.test)
    api(libs.junit)
    api(libs.turbine)
}
