import java.util.Properties

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
    compileSdk = libs.versions.androidCompileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.opencapture.openpocketcine"
        minSdk = 29
        targetSdk = 36
        versionCode = resolvedVersionCode
        versionName = resolvedVersionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Camera stress runs use android-feed-stress's explicit adb invocation.
        // Exclude before execution: UTP can report a runtime assumption as failure.
        testInstrumentationRunnerArguments["notClass"] =
            "com.opencapture.openpocketcine.FeedStressTest"
        buildConfigField("String", "SOURCE_REVISION", "\"unknown\"")
        buildConfigField("String", "SENTRY_DSN_ANDROID", "\"\"")

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

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
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
            isMinifyEnabled = false
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

// Non-empty SENTRY_DSN_ANDROID wins; otherwise optional ignored repo-root properties.
val sentryDsnAndroidField =
    providers.environmentVariable("SENTRY_DSN_ANDROID")
        .orElse("")
        .zip(
            providers.of(LocalReliabilityDsnValueSource::class.java) {
                parameters.propertiesFile.set(
                    repositoryRoot.resolve(".local/reliability.properties"),
                )
            },
        ) { env, file ->
            val raw = env.trim().ifEmpty { file.trim() }
            val escaped = raw.replace("\\", "\\\\").replace("\"", "\\\"")
            com.android.build.api.variant.BuildConfigField(
                "String",
                "\"$escaped\"",
                "optional Sentry Android DSN",
            )
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
        variant.buildConfigFields?.put("SENTRY_DSN_ANDROID", sentryDsnAndroidField)
        // Exec output participates in configuration-cache validation, so dirty
        // source edits cannot silently retain the preceding build identity.
        val identity = providers.exec {
            workingDir = repositoryRoot
            commandLine(
                pythonExecutable.get(), repositoryRoot.resolve("tools/build-identity.py").absolutePath,
                "--platform", "android", "--configuration",
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

dependencies {
    implementation(project(":core-api"))
    implementation(project(":monitor-ui"))

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
    implementation(libs.sentry.android)

    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:core:1.7.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation(libs.kotlin.test.junit)

    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.json)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)
}

abstract class LocalReliabilityDsnValueSource :
    ValueSource<String, LocalReliabilityDsnValueSource.Params> {
    interface Params : ValueSourceParameters {
        @get:org.gradle.api.tasks.Optional
        @get:InputFile
        @get:PathSensitive(PathSensitivity.NONE)
        val propertiesFile: RegularFileProperty
    }

    override fun obtain(): String {
        val file = parameters.propertiesFile.orNull?.asFile ?: return ""
        if (!file.isFile) return ""
        val props = Properties()
        file.inputStream().use { props.load(it) }
        return props.getProperty("SENTRY_DSN_ANDROID")?.trim().orEmpty()
    }
}
