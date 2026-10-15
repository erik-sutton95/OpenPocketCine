plugins {
    alias(libs.plugins.android.application)
    // BuildConfig.SENTRY_DSN_ANDROID: the CI secret, else the ignored .local/reliability.properties.
    id("com.opencapture.opencine.reporting")
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
    compileSdk = libs.versions.androidCompileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.opencapture.openpocketcine"
        minSdk = 29
        targetSdk = 36
        versionCode = resolvedVersionCode
        versionName = resolvedVersionName
        manifestPlaceholders["sentryProguardUuid"] = System.getenv("SENTRY_PROGUARD_UUID").orEmpty()
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Camera stress runs use android-feed-stress's explicit adb invocation.
        // Exclude before execution: UTP can report a runtime assumption as failure.
        testInstrumentationRunnerArguments["notClass"] =
            "com.opencapture.openpocketcine.FeedStressTest"
        buildConfigField("String", "SOURCE_REVISION", "\"unknown\"")

        ndk {
            abiFilters += supportedAndroidAbi
        }
    }

    ndkVersion = "28.2.13676358"

    // Ratchet, not a clean-up mandate: today's warnings are recorded in
    // `lint-baseline.xml`, and anything new is an error. Burn entries out of
    // the baseline as they get fixed; regenerate it with
    // `./gradlew :app:updateLintBaseline` only after a real fix, never to make
    // a new warning go away.
    lint {
        warningsAsErrors = true
        baseline = file("lint-baseline.xml")
        // These fire when somebody else publishes a release, not when this
        // repo changes — Dependabot owns them. A green CI must not depend on
        // the day's version of the world.
        informational +=
            listOf(
                "GradleDependency",
                "NewerVersionAvailable",
                "AndroidGradlePluginVersion",
                "UseTomlInstead",
            )
    }

    // Play closed testing signs with the upload keystore from the environment.
    // Debug and unsigned local release stay possible when the env is unset.
    // See docs/android-play-ci.md.
    val uploadKeystorePath = System.getenv("ANDROID_KEYSTORE_FILE").orEmpty()
    if (uploadKeystorePath.isNotEmpty()) {
        val uploadKeystore = file(uploadKeystorePath)
        require(uploadKeystore.isFile) {
            "ANDROID_KEYSTORE_FILE is set but not a file: $uploadKeystorePath"
        }
        signingConfigs {
            create("release") {
                storeFile = uploadKeystore
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                    ?: error("ANDROID_KEYSTORE_PASSWORD is required when ANDROID_KEYSTORE_FILE is set")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                    ?: error("ANDROID_KEY_ALIAS is required when ANDROID_KEYSTORE_FILE is set")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
                    ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
                    ?: error("ANDROID_KEY_PASSWORD is required when ANDROID_KEYSTORE_FILE is set")
            }
        }
    }

    buildTypes {
        debug {
            // The upstream alpha ships from Play under the release key, so a local
            // debug build can never replace it. A distinct id installs beside it and
            // keeps both available for side-by-side qualification on one body.
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (uploadKeystorePath.isNotEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        // Release code for on-device profiling (`just android-perf-soak`): debug-signed,
        // profileable from the shell, installs beside release and debug.
        create("perf") {
            initWith(getByName("release"))
            applicationIdSuffix = ".perf"
            versionNameSuffix = "-perf"
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += "release"
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
        getByName("androidTest").kotlin.srcDir(
            gradle.includedBuild("opencine").projectDir.resolve("appkit-native/src/cacheOwnerProof/kotlin"))
        getByName("main").jniLibs.directories.apply {
            clear()
            add(swiftCoreJniLibsRoot.get().asFile.absolutePath)
        }
    }
}

val sourceRevisionField =
    providers.exec {
        workingDir = repositoryRoot
        commandLine("git", "rev-parse", "--short=12", "HEAD")
        isIgnoreExitValue = true
    }.standardOutput.asText
        .zip(
            providers.exec {
                workingDir = repositoryRoot
                commandLine("git", "status", "--porcelain")
                isIgnoreExitValue = true
            }.standardOutput.asText,
        ) { rev, status ->
            val envRev =
                System.getenv("OPENPOCKETCINE_SOURCE_REVISION")
                    ?: System.getenv("GITHUB_SHA")?.take(12)
            val cleaned =
                (envRev ?: rev.trim())
                    .filter { it.isLetterOrDigit() || it == '.' || it == '-' || it == '_' }
                    .ifEmpty { "unknown" }
            val dirty =
                status.isNotBlank() || System.getenv("OPENPOCKETCINE_SOURCE_DIRTY") == "1"
            val value = if (dirty) "$cleaned+" else cleaned
            com.android.build.api.variant.BuildConfigField("String", "\"$value\"", "git source revision")
        }

// Windows CPython installs put `python` on PATH and no `python3`, so the POSIX
// name aborts the build identity exec. `PYTHON` overrides both.
val pythonExecutable: Provider<String> =
    providers.environmentVariable("PYTHON").orElse(
        providers.systemProperty("os.name").map { osName ->
            if (osName.startsWith("Windows", ignoreCase = true)) "python" else "python3"
        }
    )

androidComponents {
    onVariants { variant ->
        variant.buildConfigFields?.put("SOURCE_REVISION", sourceRevisionField)
        // Exec output participates in configuration-cache validation, so dirty
        // source edits cannot silently retain the preceding build identity.
        val identity = providers.exec {
            workingDir = repositoryRoot
            commandLine(
                pythonExecutable.get(),
                repositoryRoot.resolve("../OpenCine/scripts/sentry/build-identity.py").absolutePath,
                "--root", repositoryRoot.absolutePath, "--platform", "android", "--configuration",
                "${variant.name}-$resolvedVersionName-$resolvedVersionCode-${gradle.gradleVersion}",
            )
        }.standardOutput.asText.map { value ->
            com.android.build.api.variant.BuildConfigField(
                "String", "\"${value.trim()}\"", "content identity of build inputs",
            )
        }
        variant.buildConfigFields?.put("BUILD_IDENTITY", identity)
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
            // OpenCineMedia, OpenCineMotion, OpenCineRelay, OpenCineDJI (re-exported by
            // OpenPocketViewCore), OpenCineCore, which they depend on, and OpenCineDJIAndroid (the
            // DjiNative JNI exports): the root Package.swift takes them from the sibling OpenCine
            // checkout.
            fileTree(repositoryRoot.resolve("../OpenCine")) {
                include(
                    "Package.swift",
                    "Sources/OpenCineMedia/**",
                    "Sources/OpenCineMotion/**",
                    "Sources/OpenCineRelay/**",
                    "Sources/MonitorPresentation/**",
                    "Sources/OpenCineCameraVocabulary/**",
                    "Sources/OpenCineCore/**",
                    "Sources/OpenCineJNISupport/**",
                    "Sources/OpenCineDJI/**",
                    "Sources/OpenCineDJIAndroid/**",
                    "Sources/OpenCineJNI/**",
                    "scripts/android-stage-swift-core.sh",
                )
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

// ML Kit instantiates its ComponentRegistrar classes reflectively; a shrunk bundle without their
// constructors crashes face detection (OPENPOCKETCINE-ANDROID-18). Every bundleRelease checks the dex.
val releaseBundle = layout.buildDirectory.file("outputs/bundle/release/app-release.aab")
val verifyReleaseComponentRegistrars =
    tasks.register<Exec>("verifyReleaseComponentRegistrars") {
        group = "verification"
        description = "Fail when R8 strips a ComponentRegistrar constructor from the release bundle."
        dependsOn("bundleRelease")
        inputs.file(releaseBundle)
        environment("ANDROID_HOME", androidComponents.sdkComponents.sdkDirectory.get().asFile.absolutePath)
        commandLine(
            "bash",
            repositoryRoot.resolve("../OpenCine/scripts/android-verify-component-registrars.sh").absolutePath,
            releaseBundle.get().asFile.absolutePath,
        )
    }
tasks.matching { it.name == "bundleRelease" }.configureEach {
    finalizedBy(verifyReleaseComponentRegistrars)
}

dependencies {
    debugImplementation("com.opencapture.opencine:platform:0.1.0-SNAPSHOT")
    implementation(libs.opencine.monitor.ui)
    // Cameras and pairing pages, the connection model and the saved-camera store (SHELL-02).
    implementation(libs.opencine.appkit)
    // Capture sheets, live chrome and gimbal views over the camera vocabulary (camera-controls).
    implementation("com.opencapture.opencine:camera-controls:0.1.0-SNAPSHOT")
    implementation("com.opencapture.opencine:appkit-native:0.1.0-SNAPSHOT")
    implementation("com.opencapture.opencine:core:0.1.0-SNAPSHOT")
    implementation("com.opencapture.opencine:media:0.1.0-SNAPSHOT")
    // Live-view MediaCodec decoder (HevcDecoder), shared with OpenInstaCine.
    implementation("com.opencapture.opencine:decoder:0.1.0-SNAPSHOT")
    // Native source/publication/inspector and GLES/Vulkan owners.
    implementation("com.opencapture.opencine:native-runtime:0.1.0-SNAPSHOT")
    // Shared Media3 player recipe, port, audio meter tap and playback owner.
    implementation("com.opencapture.opencine:media3:0.1.0-SNAPSHOT")
    // DJI BLE link, datalink, wire models, gimbal programs and the CameraSession adapter, with the
    // DjiNative JNI facade this app's Swift library implements.
    implementation("com.opencapture.opencine:dji:0.1.0-SNAPSHOT")
    implementation("com.opencapture.opencine:multicam:0.1.0-SNAPSHOT")
    // libopc_vulkan.so and its JNI facade (feed.OpcVulkan), built by OpenCineCore's `:vulkan` module.
    implementation("com.opencapture.opencine:vulkan:0.1.0-SNAPSHOT")

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
    implementation(libs.mlkit.face.detection)
    // The shared reporting adapter: appkit's reporting sink, transport and problem report upload on
    // the Sentry SDK (sentry-android comes with it, at the version OpenCine pins).
    implementation("com.opencapture.opencine:appkit-sentry:0.1.0-SNAPSHOT")

    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:core:1.7.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation(libs.kotlin.test.junit)
    androidTestImplementation("com.opencapture.opencine:app-ui-testing:0.1.0-SNAPSHOT")
    androidTestImplementation(testFixtures("com.opencapture.opencine:core:0.1.0-SNAPSHOT"))

    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.json)
    testImplementation(libs.kotlinx.coroutines.test)
}
