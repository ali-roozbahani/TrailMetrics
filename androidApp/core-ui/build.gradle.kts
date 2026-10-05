plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kover)
}

android {
    namespace = "dev.roozbahani.trailmetrics.core.ui"
    compileSdk = 37
    defaultConfig {
        minSdk = 26
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(project(":core"))
    implementation(project(":domain"))

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.core.ktx)
    implementation(libs.material)

    implementation(libs.maps.compose)
    implementation(libs.play.services.maps)
}

// Coverage regression gate (`koverVerify`, run by scripts/pre-push-check.sh and CI): no floor here,
// on purpose. This module is declarative Compose UI (theme, `MetricCell`, map composables) plus the
// `RouteUiError` string mapping, and has no tests of its own, so its own line coverage is 0%
// (0/113 lines, measured 2026-10-05). A floor of 0 could never fail. Add one, set the way the
// feature modules' are, when the first test of its own runs on the Android host.
