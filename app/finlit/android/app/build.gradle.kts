import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing.
//
// The keystore and its password live OUTSIDE this repository, in the project's
// local memory directory — never in git. `key.properties` points at them and is
// itself gitignored; see docs/sborka-i-dostavka.md for where it comes from.
//
// When key.properties is absent (a teammate who has just cloned, or CI), release
// builds fall back to the debug key so the build still runs. That fallback is
// fine for `flutter run --release`, and NOT fine for anything handed to the jury
// or uploaded to RuStore: those must be signed with the real key, or the app
// cannot be updated later.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "ru.lct2026.finlit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ru.lct2026.finlit"
        // 🔴 Выставлено явно, а не через flutter.minSdkVersion.
        // Дефолт Flutter — 24 (Android 7.0), а ТЗ §3.1.1 требует Android 8.0.
        // Пока здесь дефолт, манифест, документация и карточка RuStore
        // расходятся: консоль подтягивает минимальную версию из манифеста
        // и показала бы «Android 7.0».
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
