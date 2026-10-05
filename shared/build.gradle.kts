import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFrameworkConfig

plugins {
    alias(libs.plugins.jetbrains.kotlin.multiplatform)
    alias(libs.plugins.android.kotlin.multiplatform.library)
    alias(libs.plugins.skie)
    alias(libs.plugins.kover)
}

kotlin {
    android {
        namespace = "dev.roozbahani.trailmetrics.shared"
        compileSdk = 37
        minSdk = 26
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_11)
        }
        withHostTestBuilder {}.configure {}
    }

    val xcframeworkName = "TrailMetricsShared"
    val xcf = XCFrameworkConfig(project, xcframeworkName)

    listOf(
        iosArm64(),
        iosSimulatorArm64()
    ).forEach { target ->
        target.binaries.framework {
            baseName = xcframeworkName
            isStatic = true
            export(project(":domain"))
            export(project(":data"))
            export(project(":core"))
            xcf.add(this)
        }
    }

    sourceSets {
        commonMain.dependencies {
            api(project(":domain"))
            api(project(":data"))
            api(project(":core"))
            implementation(project.dependencies.platform(libs.koin.bom))
            implementation(libs.koin.core)
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
        androidMain.dependencies {
            implementation(libs.koin.android)
        }
        iosMain.dependencies {
            // For testsupport/SwiftTestSupport.kt. domain/data use coroutines as
            // implementation, so it isn't on shared's compile classpath otherwise.
            implementation(libs.kotlinx.coroutines.core)
        }
        iosTest.dependencies {
            implementation(libs.kotlinx.coroutines.test)
        }
    }
}

// Coverage regression gate (`koverVerify`, run by scripts/pre-push-check.sh and CI): no floor here,
// on purpose. This module is the umbrella and Koin composition root (`initKoin`, platform modules,
// the iOS `KoinHelper` and XCFramework export); its only test is in iosTest, which Kover can't
// measure, so its own line coverage is 0% (0/17 lines, measured 2026-10-05). A floor of 0 could
// never fail. Add one, set the way domain's is, when the first test of its own runs on the Android
// host (commonTest or the Android host test).
