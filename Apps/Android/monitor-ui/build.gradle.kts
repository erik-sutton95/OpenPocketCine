plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.opencapture.monitorui"
    compileSdk = 36
    defaultConfig { minSdk = 29 }
    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
}

dependencies {
    api(platform(libs.compose.bom))
    api(libs.compose.material3)
    testImplementation(libs.kotlin.test.junit)
}

// Match the repository's documented SDK 36 / Compose AAR compatibility gate.
afterEvaluate {
    tasks.matching { it.name.startsWith("check") && it.name.endsWith("AarMetadata") }
        .configureEach { enabled = false }
}
