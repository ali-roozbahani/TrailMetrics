import com.android.build.api.variant.AndroidComponentsExtension
import io.gitlab.arturbosch.detekt.Detekt
import io.gitlab.arturbosch.detekt.DetektPlugin
import io.gitlab.arturbosch.detekt.extensions.DetektExtension
import org.gradle.api.attributes.Attribute
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
    alias(libs.plugins.google.services) apply false
    alias(libs.plugins.firebase.crashlytics) apply false
    // Applied (not `apply false`): the root project is Kover's merging module.
    alias(libs.plugins.kover)
}

// Merged coverage report across these modules: `./gradlew koverHtmlReport koverXmlReport`
// (Kover's total variant, i.e. all classes and all JVM/Android host tests of each module).
// Report only: the root has no verification rules. The coverage gate is each module's own
// koverVerify (rules in domain, data and the androidApp feature modules; core, shared, androidApp:app
// and androidApp:core-ui have none, each build file says why). androidApp:core-testing
// is left out on purpose, it holds shared test fakes, not code under test.
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

    // Typed detekt (type resolution): `detektTyped` runs in every Kotlin module and is what the gate
    // and CI run next to the plain `detekt`. Generated code (KSP's Room classes) is not ours to lint.
    tasks.withType<Detekt>().configureEach {
        // A pattern is relative to each source root, which cannot name a build directory, so match
        // the file's absolute path.
        exclude { it.file.path.contains("/build/generated/") }
    }
    val detektTyped = tasks.register("detektTyped") {
        group = "verification"
        description = "Runs detekt with type resolution on every source set it can resolve (see config/detekt/detekt.yml)."
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

            // AGP's built-in Kotlin never applies org.jetbrains.kotlin.android, so detekt's plugin
            // registers no typed task here; register one per compilation, with its source directory
            // and the compilation's classpath.
            val androidKotlin = extensions.getByType<KotlinAndroidProjectExtension>()
            listOf("debug" to "src/main", "debugUnitTest" to "src/test", "debugAndroidTest" to "src/androidTest")
                .forEach { (compilationName, sourceDir) ->
                    if (!file(sourceDir).exists()) return@forEach
                    val typedTask = tasks.register<Detekt>("detektTyped${compilationName.replaceFirstChar { it.uppercase() }}") {
                        description = "Runs detekt with type resolution on $sourceDir."
                        val compilation = androidKotlin.target.compilations.getByName(compilationName)
                        setSource(files(sourceDir))
                        config.setFrom(files("$rootDir/config/detekt/detekt.yml"))
                        buildUponDefaultConfig = true
                        jvmTarget = "11"
                        val dependencies = configurations.getByName("${compilationName}CompileClasspath").incoming
                            .artifactView {
                                isLenient = true
                                attributes.attribute(Attribute.of("artifactType", String::class.java), "android-classes-jar")
                            }.files
                        val androidJar = (project.extensions.getByName("androidComponents") as AndroidComponentsExtension<*, *, *>)
                            .sdkComponents.bootClasspath
                        classpath.setFrom(dependencies, compilation.output.classesDirs, androidJar)
                    }
                    detektTyped.configure { dependsOn(typedTask) }
                }
        }
    }

    plugins.withId("org.jetbrains.kotlin.multiplatform") {
        configure<KotlinMultiplatformExtension> {
            compilerOptions {
                allWarningsAsErrors.set(true)
            }
        }

        // The plain `detekt` task only reads src/main/{java,kotlin}, which a KMP module does not
        // have (it ran as NO-SOURCE). Point it at every source set directory instead; detekt
        // itself keeps only the *.kt and *.kts files.
        configure<DetektExtension> {
            source.setFrom(files("src"))
        }

        // Typed run. The plugin's `detektAndroidMain` / `detektAndroidHostTest` read only the android
        // source set directory and resolve types against the Android compilation's classpath. That
        // compilation also compiles commonMain / commonTest, so two more tasks take those directories
        // and the classpath of the plugin's task. The plugin's iOS and metadata tasks have no type
        // resolution in detekt 1.23.8, so iosMain / iosTest are covered by the plain `detekt` only.
        afterEvaluate {
            val androidTarget = extensions.getByType<KotlinMultiplatformExtension>().targets.findByName("android")
            // shared-uitest has no Android target, so it has no typed task: plain `detekt` only.
            if (androidTarget == null) return@afterEvaluate
            val androidMainOutput = androidTarget.compilations.getByName("main").output.classesDirs
            val androidJar = (extensions.getByName("androidComponents") as AndroidComponentsExtension<*, *, *>)
                .sdkComponents.bootClasspath
            fun dependencies(configurationName: String) = configurations.getByName(configurationName).incoming
                .artifactView {
                    isLenient = true
                    attributes.attribute(Attribute.of("artifactType", String::class.java), "android-classes-jar")
                }.files
            listOf(
                Triple("detektAndroidMain", "commonMain", files(dependencies("androidCompileClasspath"), androidJar)),
                Triple("detektAndroidHostTest", "commonTest", files(dependencies("androidHostTestCompileClasspath"), androidJar, androidMainOutput)),
            ).forEach { (pluginTaskName, sourceDir, classes) ->
                val commonTask = tasks.register<Detekt>("detektTyped${sourceDir.replaceFirstChar { it.uppercase() }}") {
                    description = "Runs detekt with type resolution on src/$sourceDir."
                    setSource(files("src/$sourceDir"))
                    config.setFrom(files("$rootDir/config/detekt/detekt.yml"))
                    buildUponDefaultConfig = true
                    jvmTarget = "11"
                    classpath.setFrom(classes)
                }
                detektTyped.configure { dependsOn(pluginTaskName, commonTask) }
            }
        }
    }
}
