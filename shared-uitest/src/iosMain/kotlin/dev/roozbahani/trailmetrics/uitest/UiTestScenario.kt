package dev.roozbahani.trailmetrics.uitest

/**
 * The scripted situations the iOS UI tests launch the app in. Swift matches the launch
 * argument's value against an entry's `name`.
 *
 * Every scenario has a saved user profile ([UiTestFixtures.profile]), returns
 * [UiTestFixtures.start] as the current location and the fixed closed [UiTestFixtures.route]
 * for any directions request. A held call waits until [UiTestControls.releaseHeldCalls].
 */
enum class UiTestScenario(
    internal val seedsHistory: Boolean,
    internal val heldCall: UiTestHeldCall?,
    internal val failsDelete: Boolean,
    internal val walksRoute: Boolean
) {
    /** One seeded activity; every `deleteActivity` throws. Nothing is held. */
    FailedDelete(seedsHistory = true, heldCall = null, failsDelete = true, walksRoute = false),

    /** One seeded activity; every `deleteActivity` is held until release. */
    DeleteTwice(seedsHistory = true, heldCall = UiTestHeldCall.Delete, failsDelete = false, walksRoute = false),

    /** Empty history; every `getClosedRoute` is held until release. */
    GenerateTwice(seedsHistory = false, heldCall = UiTestHeldCall.Directions, failsDelete = false, walksRoute = false),

    /** Empty history; every `getClosedRoute` is held until release. */
    GenerateThenReset(
        seedsHistory = false,
        heldCall = UiTestHeldCall.Directions,
        failsDelete = false,
        walksRoute = false
    ),

    /**
     * Empty history; every `saveActivity` is held until release. Location updates walk the route:
     * one update per route point, in order, ending at the second-to-last point (see [UiTestFixtures.route]).
     */
    FinishTwice(seedsHistory = false, heldCall = UiTestHeldCall.Save, failsDelete = false, walksRoute = true)
}

/** The repository call a scenario holds until [UiTestControls.releaseHeldCalls]. */
internal enum class UiTestHeldCall { Delete, Directions, Save }
