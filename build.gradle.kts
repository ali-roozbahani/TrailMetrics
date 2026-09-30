import io.gitlab.arturbosch.detekt.DetektPlugin
import io.gitlab.arturbosch.detekt.extensions.DetektExtension
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension
import org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension
import org.jetbrains.kotlin.gradle.dsl.KotlinMultiplatformExtension

// Top-level build file where you can add configuration options common to all sub-projects/modules.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.ksp) apply false
    alias(libs.plugins.jetbrains.kotlin.jvm) apply false
    alias(libs.plugins.jetbrains.kotlin.multiplatform) apply false
    alias(libs.plugins.android.kotlin.multiplatform.library) apply false
    alias(libs.plugins.buildkonfig) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.detekt) apply false
    // Applied (not `apply false`): the root project is Kover's merging module.
    alias(libs.plugins.kover)
}

// Merged coverage report across these modules: `./gradlew koverHtmlReport koverXmlReport`
// (Kover's total variant, i.e. all classes and all JVM/Android host tests of each module).
// Baseline only: no verification rules. androidApp:core-testing is left out on purpose,
// it holds shared test fakes, not code under test.
dependencies {
    kover(project(":domain"))
    kover(project(":data"))
    kover(project(":core"))
    kover(project(":shared"))
    kover(project(":androidApp:app"))
    kover(project(":androidApp:core-ui"))
    kover(project(":androidApp:feature-route"))
    kover(project(":androidApp:feature-tracking"))
    kover(project(":androidApp:feature-history"))
}

subprojects {
    apply<DetektPlugin>()

    configure<DetektExtension> {
        buildUponDefaultConfig = true
        config.setFrom(files("$rootDir/config/detekt/detekt.yml"))
        autoCorrect = true
    }

    plugins.withId("org.jetbrains.kotlin.jvm") {
        configure<KotlinJvmProjectExtension> {
            compilerOptions {
                allWarningsAsErrors.set(true)
            }
        }
    }

    // androidApp/* modules use AGP 9's built-in Kotlin: AGP registers the `kotlin`
    // extension itself and the org.jetbrains.kotlin.android plugin id is never applied,
    // so hook on the AGP plugin ids instead. The KMP modules apply
    // com.android.kotlin.multiplatform.library, which is covered by the multiplatform
    // block below, not by these ids.
    listOf("com.android.application", "com.android.library").forEach { agpPluginId ->
        plugins.withId(agpPluginId) {
            configure<KotlinAndroidProjectExtension> {
                compilerOptions {
                    allWarningsAsErrors.set(true)
                }
            }
        }
    }

    plugins.withId("org.jetbrains.kotlin.multiplatform") {
        configure<KotlinMultiplatformExtension> {
            compilerOptions {
                allWarningsAsErrors.set(true)
            }
        }
    }
}
