import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.jetbrains.kotlin.multiplatform)
    alias(libs.plugins.android.kotlin.multiplatform.library)
    alias(libs.plugins.kotlinx.serialization)
    alias(libs.plugins.kover)
}

kotlin {
    android {
        namespace = "dev.roozbahani.trailmetrics.core"
        compileSdk = 37
        minSdk = 26
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_11)
        }
        withHostTestBuilder {}.configure {}
    }

    iosX64()
    iosArm64()
    iosSimulatorArm64()

    sourceSets {
        commonMain.dependencies {
            implementation(project(":domain"))
            implementation(libs.kotlinx.serialization.json)
        }
    }
}

// Coverage regression gate (`koverVerify`, run by scripts/pre-push-check.sh and CI): no floor here,
// on purpose. This module holds shared declarations (`AppRoute`, `RouteUiError` and its
// `toUiError()` mapping) and has no tests of its own, so its own line coverage is 0% (0/17 lines,
// measured 2026-10-05). The root merged report shows 7 of those lines covered by the feature
// modules' ViewModel tests, which this module's koverVerify can't see. A floor of 0 could never
// fail. Add one, set the way domain's is, when the first test of its own runs on the Android host.
