import org.jetbrains.kotlin.gradle.plugin.mpp.NativeBuildType
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFrameworkConfig

// The test-only variant of TrailMetricsShared.xcframework (ADR-002, "Amendment"): the same Swift
// module as :shared's framework, with the same API plus the UI-test seam of the package
// dev.roozbahani.trailmetrics.uitest. Only UI-test builds link it: scripts/build-kmp-framework.sh
// builds it for the Debug-UITest configuration or with --variant uitest, through
// `./gradlew :shared-uitest:assembleTrailMetricsSharedDebugXCFramework`, and copies it over the
// debug path of :shared's framework. Production code never depends on this module.
plugins {
    alias(libs.plugins.jetbrains.kotlin.multiplatform)
    alias(libs.plugins.skie)
}

kotlin {
    val xcframeworkName = "TrailMetricsShared"
    val xcf = XCFrameworkConfig(project, xcframeworkName)

    listOf(
        iosArm64(),
        iosSimulatorArm64()
    ).forEach { target ->
        // DEBUG only: UI tests run against a debug build, and no Release variant may exist.
        target.binaries.framework(listOf(NativeBuildType.DEBUG)) {
            baseName = xcframeworkName
            isStatic = true
            export(project(":shared"))
            export(project(":domain"))
            export(project(":data"))
            export(project(":core"))
            xcf.add(this)
        }
    }

    sourceSets {
        iosMain.dependencies {
            api(project(":shared"))
            implementation(project.dependencies.platform(libs.koin.bom))
            implementation(libs.koin.core)
            implementation(libs.kotlinx.coroutines.core)
        }
        iosTest.dependencies {
            implementation(kotlin("test"))
            implementation(libs.kotlinx.coroutines.test)
        }
    }
}

// No Kover and no coverage floor, on purpose: the module has only iOS targets, which Kover can't
// measure, so it reads no floor (as :shared, which has none either). Don't name the floors file
// in this build file: scripts/check-kover-floors.sh counts every build file whose text names it
// as a reader that needs an entry.
