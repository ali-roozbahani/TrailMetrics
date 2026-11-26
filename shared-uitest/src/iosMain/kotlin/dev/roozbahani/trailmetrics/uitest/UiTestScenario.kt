package dev.roozbahani.trailmetrics.uitest

import dev.roozbahani.trailmetrics.domain.model.RouteError

/**
 * The scripted situations the iOS UI tests launch the app in. Swift matches the launch
 * argument's value against an entry's `name`.
 *
 * Every scenario has a saved user profile ([UiTestFixtures.profile]), returns
 * [UiTestFixtures.start] as the current location and the fixed closed [UiTestFixtures.route]
 * for any directions request (except the first one of [NoConnectionThenRoute]). A held call waits
 * until [UiTestControls.releaseHeldCalls].
 */
enum class UiTestScenario(
    internal val seedsHistory: Boolean,
    internal val heldCall: UiTestHeldCall?,
    internal val failsDelete: Boolean,
    internal val walksRoute: Boolean,
    internal val firstDirectionsHasNoConnection: Boolean = false,
    internal val sessionStore: UiTestSessionStore = UiTestSessionStore.Empty
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
    FinishTwice(seedsHistory = false, heldCall = UiTestHeldCall.Save, failsDelete = false, walksRoute = true),

    /**
     * Empty history, nothing held. The session store holds a Paused session ([UiTestFixtures.pausedSession])
     * as an app killed while paused leaves it, so the app offers it at launch.
     */
    RestoredPausedSession(
        seedsHistory = false,
        heldCall = null,
        failsDelete = false,
        walksRoute = false,
        sessionStore = UiTestSessionStore.StoresPausedSession
    ),

    /**
     * Empty history, nothing stored. The session store's read is held until release, as a slow
     * read at launch: the app must not offer Start while it lasts, and offers it after.
     */
    HeldSessionRead(
        seedsHistory = false,
        heldCall = UiTestHeldCall.Load,
        failsDelete = false,
        walksRoute = false
    ),

    /**
     * Empty history, nothing held. The first `getClosedRoute` fails with [RouteError.NoConnection], as a call
     * made offline; every later one returns the route, as a retry once connected.
     */
    NoConnectionThenRoute(
        seedsHistory = false,
        heldCall = null,
        failsDelete = false,
        walksRoute = false,
        firstDirectionsHasNoConnection = true
    ),

    /** Empty history, nothing held. Every save of the in-progress session throws, as a store that cannot write. */
    FailedSessionSave(
        seedsHistory = false,
        heldCall = null,
        failsDelete = false,
        walksRoute = false,
        sessionStore = UiTestSessionStore.FailsEverySave
    ),

    /**
     * Empty history, nothing held. Each location collection (Start) first reports the location unavailable three
     * times in a row, so the session reports a location issue, and then one fix at the route's second point. Every
     * session save after that issue throws, so the issue's error and the unsaved-session warning reach the screen
     * together.
     */
    LocationIssueThenFailedSessionSave(
        seedsHistory = false,
        heldCall = null,
        failsDelete = false,
        walksRoute = false,
        sessionStore = UiTestSessionStore.FailsSavesAfterLocationIssue
    );

    /**
     * Whether each location collection first reports the location unavailable (a location issue) and then one fix
     * (see [UiTestLocationRepository]); only [LocationIssueThenFailedSessionSave], whose store fails after that issue.
     */
    internal val reportsLocationIssueFirst: Boolean get() = this == LocationIssueThenFailedSessionSave
}

/** What a scenario's session store holds at launch, and when its saves throw. */
internal enum class UiTestSessionStore {
    /** Nothing stored; every save succeeds. */
    Empty,

    /** Holds [UiTestFixtures.pausedSession], as an app killed while paused leaves it; every save succeeds. */
    StoresPausedSession,

    /** Nothing stored; every save throws. */
    FailsEverySave,

    /** Nothing stored; every save after the location fake has reported its issue throws. */
    FailsSavesAfterLocationIssue
}

/** The repository call a scenario holds until [UiTestControls.releaseHeldCalls]. */
internal enum class UiTestHeldCall { Delete, Directions, Save, Load }
