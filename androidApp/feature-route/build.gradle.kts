plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kover)
}

android {
    namespace = "dev.roozbahani.trailmetrics.feature.route"
    compileSdk {
        version = release(37) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        minSdk = 26
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

dependencies {
    implementation(project(":domain"))
    implementation(project(":core"))
    implementation(project(":androidApp:core-ui"))

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material.icons.extended)

    // Maps - Compose
    implementation(libs.maps.compose)
    implementation(libs.play.services.maps)

    // Koin
    implementation(platform(libs.koin.bom))
    implementation(libs.koin.androidx.compose)

    testImplementation(project(":androidApp:core-testing"))
    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlinx.coroutines.test)
}

// Coverage regression gate (`koverVerify`, run by scripts/pre-push-check.sh and CI): a floor a
// little below this module's measured line coverage from its own tests (25.87%, measured on main
// after test-feature-route).
kover {
    reports {
        verify {
            rule {
                minBound(24)
            }
        }
    }
}
