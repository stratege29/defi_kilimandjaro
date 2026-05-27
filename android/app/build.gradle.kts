import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase: applies google-services.json (must be applied last).
    id("com.google.gms.google-services")
}

// Charge `android/key.properties` (gitignored) pour la clé d'upload Play
// Store. Fail-soft : si le fichier est absent (CI sans secrets / fresh
// worktree), on retombe sur la clé debug pour permettre `flutter run
// --release` local sans bloquer.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.ultimesgriots.kilimandjaro"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.ultimesgriots.kilimandjaro"
        // App Check (Play Integrity) requires minSdk >= 19. We pin to 21 to
        // stay aligned with Firebase 4.x baseline and fail fast on regressions.
        minSdk = maxOf(flutter.minSdkVersion, 21)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Lit la clé d'upload depuis `android/key.properties`.
            // Cf. https://docs.flutter.dev/deployment/android#signing-the-app
            val alias = keystoreProperties["keyAlias"] as String?
            val keyPwd = keystoreProperties["keyPassword"] as String?
            val storeFilePath = keystoreProperties["storeFile"] as String?
            val storePwd = keystoreProperties["storePassword"] as String?
            if (alias != null && keyPwd != null && storeFilePath != null && storePwd != null) {
                keyAlias = alias
                keyPassword = keyPwd
                storeFile = file(storeFilePath)
                storePassword = storePwd
            }
        }
    }

    buildTypes {
        release {
            // Si `key.properties` est présent, signe avec la clé d'upload
            // (release prête pour Play Console). Sinon, retombe sur la
            // clé debug (utile pour `flutter run --release` sans secrets).
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
