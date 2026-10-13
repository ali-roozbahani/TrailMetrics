package dev.roozbahani.trailmetrics.shared.uitest

// UI-TEST SUPPORT ONLY. This package lets the iOS UI tests (iosApp/TrailMetricsUITests) start
// the app on in-memory Kotlin fakes instead of GPS, the Directions API, the Room database and
// the user defaults, scripted per scenario by [UiTestScenario]. Production code, Kotlin or
// Swift, must not use it.
//
// The entry is meant to be called only from a DEBUG-only Swift call site in the app's
// composition root, in place of `doInitKoinIos()`. That call site does not exist yet; until it
// does, nothing calls this package.
//
// Why it lives in iosMain and ships in the XCFramework: only the iOS app needs it, and a second
// Kotlin framework could not share types with this one. Like testsupport/SwiftTestSupport.kt it
// is compiled into every build of the framework: SharedKit links the debug XCFramework for every
// build configuration, so no Kotlin code can be kept out of a Release app today (board record
// `release-build-links-debug-xcframework` tracks the Release tooling that would change that).
//
// Only three declarations are visible to Swift: [doInitKoinIosForUiTest], [UiTestScenario] and
// [UiTestControls]. Everything else in the package is internal or private. Nothing suspend and
// no Flow is visible to Swift, so no `@Throws` is declared for Swift here.

import dev.roozbahani.trailmetrics.shared.di.initKoin
import org.koin.core.context.loadKoinModules

/**
 * Starts Koin for an iOS UI test: the production modules through [initKoin], then the fakes of
 * [scenario] through [loadKoinModules], so the fakes replace the production bindings.
 *
 * Never pass the fakes through `initKoin { modules(...) }`: its declaration runs before the
 * production modules, which then replace the fakes again.
 *
 * Returns the controls of this launch. Each call after `stopKoin()` builds fresh fakes, fresh
 * counters and an unreleased gate.
 */
fun doInitKoinIosForUiTest(scenario: UiTestScenario): UiTestControls {
    val controls = UiTestControls(scenario)
    initKoin()
    loadKoinModules(uiTestOverrideModule(scenario, controls))
    return controls
}
