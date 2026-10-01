import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.jetbrains.kotlin.multiplatform)
    alias(libs.plugins.android.kotlin.multiplatform.library)
    alias(libs.plugins.kotlinx.serialization)
    alias(libs.plugins.kover)
}

kotlin {
    android {
        namespace = "dev.roozbahani.trailmetrics.domain"
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
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.serialization.json)
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            implementation(libs.kotlinx.coroutines.test)
        }
    }
}

// Coverage regression gate (`koverVerify`, run by scripts/pre-push-check.sh and CI): a floor a
// little below this module's measured line coverage from its own tests (96.76% once the
// MetricsFormatter, GenerateClosedRouteUseCase and session-manager tests landed; 76.26% before).
// Not the root merged figure, which also counts the feature ViewModel tests: a module's
// koverVerify only sees its own tests, and Kover has no per-rule filters in the merged project.
kover {
    reports {
        verify {
            rule {
                minBound(95)
            }
        }
    }
}
