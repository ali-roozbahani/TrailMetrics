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
            implementation(project.dependencies.platform(libs.koin.bom))
            implementation(libs.koin.test)
        }
        androidMain.dependencies {
            implementation(libs.koin.android)
        }
    }
}

// Coverage regression gate (`koverVerify`, run by scripts/pre-push-check.sh and CI): a floor a
// little below this module's measured line coverage from its own tests (100% on the Android host,
// 2026-10-22: `initKoin` and the Android platform modules, which the Koin graph test resolves; the
// iOS-only `KoinHelper` is not measured on the host). The test is `KoinGraphAndroidTest` and, for
// iOS, `KoinGraphIosTest`; the Swift test support's tests are in :shared-uitest.
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
