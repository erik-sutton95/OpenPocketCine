plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

val supportedAndroidAbi = "arm64-v8a"
val swiftCoreJniLibsRoot = layout.buildDirectory.dir("generated/swiftCore/jniLibs")
val swiftCoreArm64Directory = swiftCoreJniLibsRoot.map { it.dir(supportedAndroidAbi) }
val repositoryRoot = rootProject.projectDir.parentFile.parentFile
val stageSwiftCoreScript = repositoryRoot.resolve("scripts/android-stage-swift-core.sh")

val resolvedVersionCode: Int =
    (findProperty("versionCode") ?: property("openpocketcine.versionCode")).toString().toInt()
val resolvedVersionName: String = property("openpocketcine.versionName").toString()

android {
    namespace = "com.opencapture.openpocketcine"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.opencapture.openpocketcine"
        minSdk = 29
        targetSdk = 36
        versionCode = resolvedVersionCode
        versionName = resolvedVersionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            abiFilters += supportedAndroidAbi
        }
        externalNativeBuild {
            cmake {
                arguments += "-DANDROID_STL=c++_static"
            }
        }
    }

    ndkVersion = "28.2.13676358"

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    sourceSets {
        getByName("main").jniLibs.directories.apply {
            clear()
            add(swiftCoreJniLibsRoot.get().asFile.absolutePath)
        }
    }
}

val stageSwiftCore =
    tasks.register<Exec>("stageSwiftCore") {
        group = "build"
        description = "Cross-compile and stage the Swift camera core for arm64-v8a."
        workingDir = repositoryRoot
        inputs.files(
            fileTree(repositoryRoot) {
                include("Package.swift", "Package.resolved", "Sources/**")
            },
            stageSwiftCoreScript,
        )
        inputs.property("swiftExecutable", providers.environmentVariable("SWIFT_EXECUTABLE").orElse("auto"))
        inputs.property(
            "swiftAndroidSdk",
            providers.environmentVariable("SWIFT_ANDROID_SDK_ID").orElse("swift-6.3.3-RELEASE_android"),
        )
        outputs.dir(swiftCoreArm64Directory)
        commandLine(
            "bash",
            stageSwiftCoreScript.absolutePath,
            "--output",
            swiftCoreArm64Directory.get().asFile.absolutePath,
        )
    }

tasks.named("preBuild").configure {
    dependsOn(stageSwiftCore)
}

// Compose BOM / androidx.core AARs currently declare compileSdk 37. Local and
// CI SDKs stay on 36 (same gate OpenZCine uses). Disable only the AAR metadata
// check so the rest of the AGP graph still runs.
afterEvaluate {
    tasks.matching { it.name.startsWith("check") && it.name.endsWith("AarMetadata") }
        .configureEach { enabled = false }
}

dependencies {
    implementation(project(":core-api"))

    implementation(platform(libs.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.kyant.backdrop)
    implementation(libs.kyant.shapes)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.media3.common)
    implementation(libs.media3.effect)
    implementation(libs.media3.exoplayer)
    implementation(libs.media3.ui)
    implementation(libs.okhttp)

    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.json)
    testImplementation(libs.kotlinx.coroutines.test)
}
