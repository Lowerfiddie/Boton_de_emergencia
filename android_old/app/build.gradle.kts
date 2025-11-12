plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services") // habilítalo si usas Firebase
}

android {
    namespace = "teckali.com.boton_de_emergencia"
    compileSdk = 35

    defaultConfig {
        applicationId = "teckali.com.boton_de_emergencia"
        minSdk = 21
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"

        multiDexEnabled = true
    }

    buildTypes {
        debug {
            // Para asegurar APK “universal” mientras depuras
            // Si tu proyecto tenía splits, puedes desactivarlos en debug:
            isMinifyEnabled = false
            // applicationIdSuffix = ".debug"
        }
        release {
            isMinifyEnabled = false
            // proguardFiles(
            //     getDefaultProguardFile("proguard-android-optimize.txt"),
            //     "proguard-rules.pro"
            // )
        }
    }

    // Con AGP 8+ ya no se usa source/targetCompatibility a este nivel para Kotlin
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    // Si tu app había habilitado splits, Flutter suele manejarlos,
    // pero puedes forzar no-splits en debug para evitar el error:
    // androidComponents { beforeVariants(selector().withBuildType("debug")) { it.enable = true } }

    packaging {
        // Si usas Flutter + libs nativas (ffmpeg, etc.) a veces necesitas excluir duplicados
        // resources.excludes += setOf("META-INF/*")
    }
}

dependencies {
    // Desugaring (si lo usas)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")

    // Si usas Kotlin stdlib explícita (no siempre necesario)
    implementation("org.jetbrains.kotlin:kotlin-stdlib")

    // Multidex si te lo pide
    implementation("androidx.multidex:multidex:2.0.1")
}