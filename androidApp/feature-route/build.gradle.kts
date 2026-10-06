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
// The number is this module's entry in config/kover-floors.properties (key: the directory name),
// which scripts/check-kover-floors.sh lets only go up; no file, no entry or no integer fails the build.
val koverFloorsFile = layout.settingsDirectory.file("config/kover-floors.properties")
val koverFloor: Int = run {
    val text = providers.fileContents(koverFloorsFile).asText.orNull
        ?: throw GradleException("${koverFloorsFile.asFile} is missing: it holds the Kover floor of $path")
    val value = text.lines().filter { it.substringBefore('=').trim() == projectDir.name && !it.startsWith("#") }
        .singleOrNull()?.substringAfter('=', "")
        ?: throw GradleException("${koverFloorsFile.asFile} needs one entry '${projectDir.name}' (Kover floor of $path)")
    value.trim().toIntOrNull()?.takeIf { it in 0..100 }
        ?: throw GradleException("${koverFloorsFile.asFile}: '${projectDir.name}=$value' is not an integer from 0 to 100")
}
kover {
    reports {
        verify {
            rule {
                minBound(koverFloor)
            }
        }
    }
}
