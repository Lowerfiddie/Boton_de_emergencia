plugins {
    id("com.android.application") version "8.6.1" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
    id("com.google.gms.google-services") version "4.4.4" apply false
}

// Limpieza estándar
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}