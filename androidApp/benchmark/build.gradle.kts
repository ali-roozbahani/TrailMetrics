plugins {
    alias(libs.plugins.android.test)
}

// Macrobenchmark of the app's cold start (docs/performance/android-cold-start.md). A com.android.test module:
// it builds a separate test APK that drives the app's `benchmark` build type from outside, so nothing here
// ships in the app. Run on a device or emulator with `:androidApp:benchmark:connectedBenchmarkAndroidTest`;
// the gate and CI build it but never run it.
android {
    namespace = "dev.roozbahani.trailmetrics.benchmark"
    compileSdk {
        version = release(37) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        minSdk = 26
        targetSdk = 37
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        // Matches the app's `benchmark` build type, which is what the test installs and measures.
        create("benchmark") {
            isDebuggable = true
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += listOf("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    targetProjectPath = ":androidApp:app"
    // The test APK instruments itself; the app under test runs in its own process, as a user's would.
    experimentalProperties["android.experimental.self-instrumenting"] = true
}

// The release variant would target the app's unsigned release APK, which cannot be installed.
androidComponents {
    beforeVariants(selector().withBuildType("release")) { variant ->
        variant.enable = false
    }
}

dependencies {
    implementation(libs.androidx.junit)
    implementation(libs.androidx.test.uiautomator)
    implementation(libs.androidx.benchmark.macro.junit4)
}
