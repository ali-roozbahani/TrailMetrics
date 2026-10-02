package dev.roozbahani.trailmetrics.shared.testsupport

// TEST SUPPORT ONLY. These types exist so Swift unit tests (iosApp/Packages/*/Tests) can
// build real Kotlin coroutine values for their fakes. Production code, Kotlin or Swift,
// must not use them.
//
// Why they're needed: the XCFramework exports no Kotlin flow or scope factory, and Swift
// can't implement one itself. A Flow written in Swift crashes on its first emission
// ("Flow invariant is violated: Emission from another coroutine"), because Kotlin requires
// emissions from the collecting coroutine and a call from Swift always runs in a new one.
// Likewise, a `suspend fun ...: Result<T>` implemented in Swift must hand Kotlin a boxed
// kotlin.Result, which isn't exported, so a Swift fake can't build one. Returning the
// plain value crashes with "ClassCastException: ... cannot be cast to kotlin.Result".
// These live in iosMain because only Swift needs them; they ship in the XCFramework
// because a second Kotlin framework can't share types with this one.

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.asFlow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlin.coroutines.CoroutineContext

/**
 * A cold [Flow] that emits [values] in order, then completes. Each collection starts over.
 *
 * A class rather than a generic function so Swift keeps the element type, e.g.
 * `SkieSwiftFlow<[ActivityRecord]>(SkieKotlinFlow(SwiftTestFlow<NSArray>(values: lists)))`.
 */
class SwiftTestFlow<T>(values: List<T>) : Flow<T> by values.asFlow()

/**
 * Like [SwiftTestFlow], but after emitting [values] it fails with an [IllegalStateException]
 * instead of completing, standing in for a failing repository flow (e.g. Room's).
 */
class SwiftFailingTestFlow<T>(values: List<T>) : Flow<T> by flow({
    emitAll(values.asFlow())
    throw IllegalStateException("SwiftFailingTestFlow failure")
})

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

/**
 * Builds the boxed `kotlin.Result` a Swift fake returns from a Kotlin `suspend` method
 * declared as returning `Result<T>` (SKIE shows it to Swift as `async throws -> Any?`),
 * e.g. `SwiftTestResult.shared.failure(exception: RouteErrorMissingLocationPermission())`.
 *
 * The return type is `Any?` on purpose: it forces Kotlin to box the `Result` value class,
 * which is the representation the calling Kotlin code casts back to.
 */
object SwiftTestResult {
    /** A successful `Result` holding [value]. */
    fun success(value: Any?): Any? = Result.success(value)

    /** A failed `Result`; `getOrThrow()` on it rethrows [exception]. */
    fun failure(exception: Throwable): Any? = Result.failure<Any?>(exception)
}
