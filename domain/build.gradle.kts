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
