plugins {
    alias(libs.plugins.android.library)
}

// Test fakes shared by the androidApp/feature-* JVM test source sets. Consumed only through
// testImplementation, so nothing here reaches the production APK.
android {
    namespace = "dev.roozbahani.trailmetrics.core.testing"
    compileSdk {
        version = release(37) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

dependencies {
    implementation(project(":domain"))
    implementation(libs.kotlinx.coroutines.core)
}
