plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.3.0"))
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

android {
    namespace = "teckali.com.boton_de_emergencia"
    compileSdk = 36

    defaultConfig {
        applicationId = "teckali.com.boton_de_emergencia"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
