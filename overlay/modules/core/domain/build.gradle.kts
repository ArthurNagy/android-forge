plugins {
    id("android-forge.jvm.library")
}

dependencies {
    // Entities and Result<V, E> appear in use-case public signatures: `api` so they flow to
    // :core:data and the features.
    api(project(":core:model"))
    api(libs.kotlin.result)
    api(libs.kotlinx.coroutines.core)
    implementation(libs.kotlin.result.coroutines) // coroutineBinding for multi-step use cases
    implementation(libs.javax.inject) // @Inject constructors; Hilt builds use cases, :core:domain stays pure Kotlin

    testImplementation(project(":core:testing"))
}
