package dev.roozbahani.trailmetrics.uitest

// UI-TEST SUPPORT ONLY. This package lets the iOS UI tests (iosApp/TrailMetricsUITests) start
// the app on in-memory Kotlin fakes instead of GPS, the Directions API, the Room database and
// the user defaults, scripted per scenario by [UiTestScenario]. Production code, Kotlin or
// Swift, must not use it.
//
// It lives in the module shared-uitest, never in shared: this module builds a test-only variant
// of TrailMetricsShared.xcframework (the same Swift module, the same API plus this package), and
// only UI-test builds link that variant (ADR-002, "Amendment"). Normal Debug and Release builds
// link shared's own framework, which contains none of this.
//
// The entry is meant to be called only from a Swift call site in the app's composition root,
// compiled only in the Debug-UITest build configuration, in place of `doInitKoinIos()`. That
// configuration and that call site come with later subtasks of docs/epics/ios-ui-tests.md (S2,
// S3); until they exist, nothing calls this package.
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
