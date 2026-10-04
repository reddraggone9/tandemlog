plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Package the canonical Rust cdylib for the existing three supported ABIs.
// Rust/std targets, reviewed Cargo inputs and the exact NDK are bootstrapped
// separately; application builds never fetch dependencies or install tools.
val textEngineJni = layout.buildDirectory.dir("generated/text_engine/jniLibs")
val buildTextEngine by tasks.registering(Exec::class) {
    val repository = rootProject.projectDir.parentFile
    inputs.dir(repository.resolve("native/text_engine"))
    inputs.file(repository.resolve("tool/build_text_engine.py"))
    outputs.dir(textEngineJni)
    workingDir(repository)
    commandLine(
        providers.gradleProperty("textEnginePython").getOrElse("python3"),
        repository.resolve("tool/build_text_engine.py").absolutePath,
        "--platform", "android",
        "--output-dir", textEngineJni.get().asFile.absolutePath,
    )
}
tasks.named("preBuild") { dependsOn(buildTextEngine) }

// Release signing is supplied only by the authorized candidate job or owner.
// Never fall back to the SDK debug identity for a distributable release.
val releaseStore = System.getenv("ANDROID_KEYSTORE_PATH")
val releaseStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
val releaseAlias = System.getenv("ANDROID_KEY_ALIAS")
val releaseKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStore, releaseStorePassword, releaseAlias, releaseKeyPassword
).all { !it.isNullOrBlank() }
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release") }) {
        check(hasReleaseSigning) { "Release signing inputs are required; debug fallback is forbidden." }
        check(file(releaseStore!!).isFile) { "Release keystore file is missing." }
    }
}

android {
    namespace = "com.reddraggone9.tandemlog"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    // AGP 9.1 SourceSet accepts a concrete File, not a Directory Provider.
    // preBuild above explicitly depends on the producer before native merging.
    sourceSets.getByName("main").jniLibs.srcDir(textEngineJni.get().asFile)

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.reddraggone9.tandemlog"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("ownerRelease") {
            if (hasReleaseSigning) {
                storeFile = file(releaseStore!!)
                storePassword = releaseStorePassword
                keyAlias = releaseAlias
                keyPassword = releaseKeyPassword
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("ownerRelease")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
