import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signing rilis: kredensial dibaca dari android/key.properties (tidak pernah di-commit).
// File itu dibuat oleh CI dari GitHub Secrets, atau manual untuk build lokal (docs/RILIS.md).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.nyatet.nyatet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nyatet.nyatet"
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
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    // REL-04: dua jalur build dengan applicationId & versionCode yang sama.
    // `sideload` memuat cek update GitHub; `play` tidak boleh memuatnya.
    flavorDimensions += "dist"
    productFlavors {
        create("sideload") {
            dimension = "dist"
            applicationId = "com.nyatet.nyatet"
        }
        create("play") {
            dimension = "dist"
            applicationId = "com.nyatet.nyatet"
        }
    }

    buildTypes {
        release {
            // Rilis WAJIB ditandatangani keystore rilis, tidak pernah debug key.
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release") else null
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

// Jangan pernah menghasilkan artefak rilis tanpa keystore rilis.
tasks.configureEach {
    if (name.startsWith("packageRelease") || name.startsWith("assembleRelease") || name.startsWith("bundleRelease")) {
        doFirst {
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(
                    "android/key.properties tidak ada. Build rilis wajib memakai keystore rilis " +
                        "(lihat docs/RILIS.md); kunci debug tidak dipakai untuk rilis."
                )
            }
        }
    }
}
