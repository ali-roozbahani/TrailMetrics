package dev.roozbahani.trailmetrics.shared.testsupport

// TEST SUPPORT ONLY. These types exist so Swift unit tests (iosApp/Packages/*/Tests) can
// build real Kotlin coroutine values for their fakes. Production code, Kotlin or Swift,
// must not use them.
//
// Why they're needed: the XCFramework exports no Kotlin flow or scope factory, and Swift
// can't implement one itself. A Flow written in Swift crashes on its first emission
// ("Flow invariant is violated: Emission from another coroutine"), because Kotlin requires
// emissions from the collecting coroutine and a call from Swift always runs in a new one.
// These live in iosMain because only Swift needs them; they ship in the XCFramework
// because a second Kotlin framework can't share types with this one.

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.asFlow
import kotlin.coroutines.CoroutineContext

/**
 * A cold [Flow] that emits [values] in order, then completes. Each collection starts over.
 *
 * A class rather than a generic function so Swift keeps the element type, e.g.
 * `SkieSwiftFlow<[ActivityRecord]>(SkieKotlinFlow(SwiftTestFlow<NSArray>(values: lists)))`.
 */
class SwiftTestFlow<T>(values: List<T>) : Flow<T> by values.asFlow()

/**
 * A [CoroutineScope] with the same context production gives `TrackingSessionManager` on
 * both platforms (`SupervisorJob() + Dispatchers.Default`, see CommonTrackingModule), for
 * constructing it in Swift tests. Call [cancel] when the test ends.
 */
class SwiftTestScope : CoroutineScope {
    override val coroutineContext: CoroutineContext = SupervisorJob() + Dispatchers.Default

    /** Cancels every coroutine launched in this scope. */
    fun cancel() {
        coroutineContext.cancel()
    }
}
