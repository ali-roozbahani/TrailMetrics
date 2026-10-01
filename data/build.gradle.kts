import com.codingfeline.buildkonfig.compiler.FieldSpec.Type.STRING
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    alias(libs.plugins.jetbrains.kotlin.multiplatform)
    alias(libs.plugins.android.kotlin.multiplatform.library)
    alias(libs.plugins.ksp)
    alias(libs.plugins.kotlinx.serialization)
    alias(libs.plugins.room)
    alias(libs.plugins.buildkonfig)
    alias(libs.plugins.kover)
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        load(localPropertiesFile.inputStream())
    }
}

room3 {
    schemaDirectory("$projectDir/schemas")
}

kotlin {
    android {
        namespace = "dev.roozbahani.trailmetrics.data"
        compileSdk = 37
        minSdk = 26
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_11)
        }
        androidResources {
            enable = true
        }
        withHostTestBuilder {}.configure {}
    }

    iosArm64()
    iosSimulatorArm64()

    targets.all {
        compilations.all {
            compileTaskProvider.configure {
                compilerOptions {
                    freeCompilerArgs.add("-Xexpect-actual-classes")
                }
            }
        }
    }

    sourceSets {
        commonMain.dependencies {
            implementation(project(":domain"))
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.serialization.json)
            implementation(libs.androidx.room.runtime)
            implementation(libs.ktor.client.core)
            implementation(libs.ktor.client.content.negotiation)
            implementation(libs.ktor.serialization.kotlinx.json)
            implementation(project.dependencies.platform(libs.koin.bom))
            implementation(libs.koin.core)
            implementation(libs.androidx.sqlite.bundled)
        }
        commonTest.dependencies {
            implementation(libs.kotlin.test)
            implementation(libs.kotlinx.coroutines.test)
            implementation(libs.ktor.client.mock)
        }
        androidMain.dependencies {
            implementation(libs.androidx.core.ktx)
            implementation(libs.kotlinx.coroutines.android)
            implementation(libs.play.services.location)
            implementation(libs.ktor.client.okhttp)
            implementation(libs.koin.android)
        }
        iosMain.dependencies {
            implementation(libs.ktor.client.darwin)
        }
        getByName("androidHostTest") {
            dependencies {
                implementation(libs.junit)
                implementation(libs.kotlinx.coroutines.test)
                implementation(libs.robolectric)
                implementation(libs.androidx.test.core)
            }
        }
    }
}

dependencies {
    add("kspAndroid", libs.androidx.room.compiler)
    add("kspIosArm64", libs.androidx.room.compiler)
    add("kspIosSimulatorArm64", libs.androidx.room.compiler)
}

buildkonfig {
    packageName = "dev.roozbahani.trailmetrics.data"

    defaultConfigs {
        buildConfigField(
            STRING,
            "DIRECTIONS_API_KEY",
            localProperties.getProperty("DIRECTIONS_API_KEY", "")
        )
        buildConfigField(STRING, "ANDROID_CERT_SHA1", "")
    }

    targetConfigs {
        create("android") {
            buildConfigField(
                STRING,
                "ANDROID_CERT_SHA1",
                localProperties.getProperty("ANDROID_CERT_SHA1", "")
            )
        }
    }
}

// Coverage regression gate (`koverVerify`, run by scripts/pre-push-check.sh and CI): a floor a
// little below this module's measured line coverage from its own host tests (19.68%, 62/315
// lines, once ActivityHistoryRepositoryImplTest ran on the host; generated code excluded). Room's
// KSP output and BuildKonfig are excluded here only, so the root merged report still shows raw
// numbers. Kover can't measure the iOS test run.
kover {
    reports {
        filters {
            excludes {
                classes(
                    "dev.roozbahani.trailmetrics.data.BuildKonfig",
                    "dev.roozbahani.trailmetrics.data.local.dao.ActivityDao_Impl",
                    "dev.roozbahani.trailmetrics.data.local.dao.ActivityDao_Impl$*",
                    "dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase_Impl",
                    "dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase_Impl$*",
                    "dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabaseConstructor",
                )
            }
        }
        verify {
            rule {
                minBound(18)
            }
        }
    }
}

afterEvaluate {
    tasks.matching {
        it.name.startsWith("lint") || it.name.startsWith("generate") && it.name.contains(
            "LintModel"
        )
    }.configureEach {
        tasks.findByName("kspAndroidHostTest")?.let { kspTask ->
            mustRunAfter(kspTask)
        }
    }
}
