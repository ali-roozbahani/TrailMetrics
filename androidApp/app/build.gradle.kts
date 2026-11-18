import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlinx.serialization)
    alias(libs.plugins.kover)
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        load(localPropertiesFile.inputStream())
    }
}

android {
    namespace = "dev.roozbahani.trailmetrics"
    compileSdk {
        version = release(37) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "dev.roozbahani.trailmetrics"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        manifestPlaceholders["MAPS_API_KEY"] = localProperties.getProperty("MAPS_API_KEY", "")
    }

    buildTypes {
        release {
            optimization {
                enable = false
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures {
        compose = true
    }

    // The unit tests run on the JVM under Robolectric and read this module's manifest and resources.
    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
}

dependencies {
    implementation(project(":core"))
    implementation(project(":domain"))
    implementation(project(":data"))
    implementation(project(":shared"))
    implementation(project(":androidApp:core-ui"))
    implementation(project(":androidApp:feature-route"))
    implementation(project(":androidApp:feature-tracking"))
    implementation(project(":androidApp:feature-history"))

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)

    // Koin
    implementation(platform(libs.koin.bom))
    implementation(libs.koin.android)
    implementation(libs.koin.androidx.compose)

    // Navigation
    implementation(libs.androidx.navigation.compose)
    implementation(libs.kotlinx.serialization.json)

    // Icons
    implementation(libs.androidx.compose.material.icons.extended)

    testImplementation(project(":androidApp:core-testing"))
    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.robolectric)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    testImplementation(libs.androidx.compose.ui.test.manifest)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.test.uiautomator)
    androidTestImplementation(libs.kotlin.test)

    debugImplementation(libs.androidx.compose.ui.test.manifest)
    debugImplementation(libs.androidx.compose.ui.tooling)
}

// Coverage regression gate (`koverVerify`, run by scripts/pre-push-check.sh and CI): a floor a
// little below this module's measured line coverage from its own tests (60.1% on 2026-11-18). This module is
// the app shell (Application, Koin start, `MainActivity` with the nav host, bottom bar and nav types).
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
