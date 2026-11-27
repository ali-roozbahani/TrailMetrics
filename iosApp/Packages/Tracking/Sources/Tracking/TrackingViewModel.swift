//
//  TrackingViewModel.swift
//  Tracking
//

import Foundation
import SharedKit

@MainActor
public class TrackingViewModel: ObservableObject {
    @Published public private(set) var trackingState: TrackingState = TrackingStateIdle.shared
    /// The time the metrics panel shows, computed when read (`domain`'s `displayedElapsedMillis` at the monotonic
    /// clock's now): while Tracking it moves between location events. Not published: `MetricsDisplay` reads it
    /// once a second while it is on screen (a `TimelineView`), so nothing ticks for a hidden screen or in the
    /// background, and a tick re-renders the metrics panel only. Display only; the Live Activity gets the
    /// recorded `elapsedMillis` (its own timer ticks).
    public var displayedElapsedMillis: Int64 {
        trackingState.displayedElapsedMillis(nowElapsedRealtimeMillis: clock.elapsedRealtimeMillis())
    }
    @Published public private(set) var calories: Double?
    /// How far along the planned route the session is, as the manager reports it (nil before the first fix
    /// and without a plan). The route's end is the manager's rule: it ends the session itself.
    @Published public private(set) var routeProgress: RouteProgress?
    /// Set when the user discards the session (Stop, Stop & Exit): the screen is on its way out.
    @Published public private(set) var isDiscarding = false

    public let activityType: ActivityType
    public let plannedRoutePoints: [Coordinates]
    public let startPoint: Coordinates

    /// The one-shot events and the ones kept while no consumer is active.
    private let events = TrackingEventChannel()

    /// The one source of "the app is still reading the stored session" (`isRestoring`): `canStart` and
    /// `onStartClicked()` read it here, nothing is copied, so a caller cannot skip the gate.
    private let storedSessionReadState: any StoredSessionReadState
    private let trackingSessionManager: TrackingSessionManager
    private let userProfileRepository: UserProfileRepository
    private let trackingMetricsUseCase: TrackingMetricsUseCase
    private let saveActivityUseCase: SaveActivityUseCase
    private let clock: Clock

    private var loadedUserProfile: UserProfile?
    /// True while the load started in `init` runs; a Finish in that time does nothing.
    private var isLoadingUserProfile = false
    /// Set before a save starts, so a repeated Finish neither saves twice nor calls `onSaved`
    /// twice; cleared when the save fails (retry) and when a new session starts. Published: `canDiscardFinished`.
    @Published private(set) var isSessionSaved = false
    /// Set while the discard of a Finished session runs (`onDiscardFinishedClicked`), so it runs once.
    @Published private(set) var isDiscardingFinished = false
    func markDiscardingFinished(_ isRunning: Bool) { isDiscardingFinished = isRunning }

    // Kotlin's `trackingScope` runs on `Dispatchers.Default`, so `for await` can resume off the main actor
    // despite @MainActor. The tasks are stored so `onStopClicked()` cancels them deterministically.
    // The state, route progress and location issues observations, cancelled together.
    private var observationTasks: [Task<Void, Never>] = []

    private var liveActivityController: TrackingLiveActivityController?
    /// Set when the Live Activity of the session was ended (by Stop or by the observed Finished state), so it
    /// ends once; cleared when a session starts or resumes.
    private var isLiveActivityEnded = false

    /// The controls the user may use now. The rules are `domain`'s (`availableControls`, the same ones
    /// Android asks); this only reads them.
    var controls: TrackingControls {
        trackingState.availableControls(isRestoring: storedSessionReadState.isRestoring)
    }

    public var canStart: Bool { controls.canStart }

    public var canPause: Bool { controls.canPause }

    /// A Finished session waits to be saved: the route's end, or a restored one. Not while it is discarded
    /// (a presentation detail of this screen: Stop passes through Finished on its way to Idle).
    public var canFinish: Bool { controls.canSave && !isDiscarding && !isDiscardingFinished }

    public var canResume: Bool { controls.canResume }

    private var isPaused: Bool {
        if case .paused = onEnum(of: trackingState) { return true }
        return false
    }

    public var canStop: Bool { controls.canStop }

    public var currentPath: [Coordinates] {
        switch onEnum(of: trackingState) {
        case .tracking(let data): return data.metrics.path
        case .paused(let data): return data.metrics.path
        default: return []
        }
    }

    /// The GPS points of the session in every state that has them, Finished included (`currentPath` stops at
    /// Tracking and Paused): the map draws it, and the snapshot Finish saves is taken in Finished.
    public var recordedPath: [Coordinates] {
        switch onEnum(of: trackingState) {
        case .tracking(let data): return data.metrics.path
        case .paused(let data): return data.metrics.path
        case .finished(let data): return data.metrics.path
        case .idle: return []
        }
    }

    /// What the metrics panel shows, from the shared `TrackingMetricsUseCase` (the same one Android uses).
    private var metricsSummary: TrackingMetricsSummary {
        trackingMetricsUseCase.invoke(
            state: trackingState,
            activityType: activityType,
            weightKg: loadedUserProfile.map { KotlinDouble(value: $0.weightKg) }
        )
    }

    /// The numbers the metrics panel shows: in every state that has a session, Finished included, so the panel
    /// stays above the Finish card after Stop and after a restore of a Finished session (as on Android).
    public var currentMetrics: TrackingMetrics? { metricsSummary.metrics }

    public convenience init(
        activityType: ActivityType,
        plannedRoutePoints: [Coordinates],
        startPoint: Coordinates,
        storedSessionReadState: any StoredSessionReadState,
        trackingSessionManager: TrackingSessionManager = KoinHelper().trackingSessionManager(),
        userProfileRepository: UserProfileRepository = KoinHelper().userProfileRepository(),
        trackingMetricsUseCase: TrackingMetricsUseCase = KoinHelper().trackingMetricsUseCase(),
        saveActivityUseCase: SaveActivityUseCase = KoinHelper().saveActivityUseCase(),
        clock: Clock = KoinHelper().clock()
    ) {
        self.init(
            activityType: activityType,
            plannedRoutePoints: plannedRoutePoints,
            startPoint: startPoint,
            storedSessionReadState: storedSessionReadState,
            trackingSessionManager: trackingSessionManager,
            userProfileRepository: userProfileRepository,
            trackingMetricsUseCase: trackingMetricsUseCase,
            saveActivityUseCase: saveActivityUseCase,
            clock: clock,
            liveActivityClient: ActivityKitLiveActivityClient()
        )
    }

    /// The designated init: the Live Activity client is internal (its protocol is), so a test passes a fake.
    init(
        activityType: ActivityType,
        plannedRoutePoints: [Coordinates],
        startPoint: Coordinates,
        storedSessionReadState: any StoredSessionReadState,
        trackingSessionManager: TrackingSessionManager,
        userProfileRepository: UserProfileRepository,
        trackingMetricsUseCase: TrackingMetricsUseCase,
        saveActivityUseCase: SaveActivityUseCase,
        clock: Clock,
        liveActivityClient: LiveActivityClient
    ) {
        self.activityType = activityType
        self.plannedRoutePoints = plannedRoutePoints
        self.startPoint = startPoint
        self.storedSessionReadState = storedSessionReadState
        self.trackingSessionManager = trackingSessionManager
        self.userProfileRepository = userProfileRepository
        self.trackingMetricsUseCase = trackingMetricsUseCase
        self.saveActivityUseCase = saveActivityUseCase
        self.clock = clock

        loadUserProfile()
        observeTrackingState()
        observeRouteProgress()
        observeLocationIssues()
        let showSaveWarning: @MainActor () -> Void = { [weak self] in self?.emit(.sessionNotSaved) }
        observationTasks.append(observeUnsavedSessionWarning(of: trackingSessionManager, onRaised: showSaveWarning))

        liveActivityController = TrackingLiveActivityController(client: liveActivityClient) { [weak self] in
            self?.handleStopNotification()
        }
    }

    public func makeEventsStream() -> AsyncStream<TrackingUiEvent> {
        let isRaised = trackingSessionManager.unsavedSessionWarning.isRaised.value.boolValue
        return events.makeStream(isSessionNotSavedRaised: isRaised)
    }

    private func emit(_ event: TrackingUiEvent) {
        events.emit(event)
    }

    private func loadUserProfile() {
        isLoadingUserProfile = true
        Task {
            defer { isLoadingUserProfile = false }
            do {
                loadedUserProfile = try await userProfileRepository.getUserProfile()
                recomputeCalories()
            } catch {
                // Without a profile there are no calories; Finish reads the profile again.
                emit(.showError(RouteUiErrorGeneral.shared))
            }
        }
    }

    private func observeTrackingState() {
        observationTasks.append(Task { [weak self] in
            guard let flow = self?.trackingSessionManager.currentState else { return }
            for await state in flow {
                guard let self else { return }
                await MainActor.run {
                    self.trackingState = state
                    self.recomputeCalories()
                    if let metrics = self.currentMetrics {
                        self.liveActivityController?.update(
                            distanceMeters: metrics.distanceMeters,
                            elapsedMillis: metrics.elapsedMillis,
                            currentSpeedMetersPerSecond: metrics.currentSpeedMetersPerSecond
                                .map { Double(truncating: $0) },
                            isPaused: self.isPaused
                        )
                    }
                    // A session the manager finishes by itself (the route's end) ends the Live Activity
                    // without the View calling `onStopClicked()`.
                    if case .finished = onEnum(of: self.trackingState) {
                        self.endLiveActivity()
                    }
                }
            }
        })
    }

    private func observeRouteProgress() {
        observationTasks.append(Task { [weak self] in
            guard let flow = self?.trackingSessionManager.routeProgress else { return }
            for await progress in flow {
                guard let self else { return }
                await MainActor.run {
                    self.routeProgress = progress
                }
            }
        })
    }

    private func observeLocationIssues() {
        observationTasks.append(Task { [weak self] in
            guard let flow = self?.trackingSessionManager.locationIssues else { return }
            for await issue in flow {
                guard let self else { return }
                await MainActor.run {
                    self.emit(.showError(issue.toUiError()))
                }
            }
        })
    }

    /// The View showed `.sessionNotSaved`: the warning is not offered again for this session.
    public func onSessionNotSavedShown() {
        trackingSessionManager.unsavedSessionWarning.markShown()
    }

    deinit {
        observationTasks.forEach { $0.cancel() }
    }

    private func recomputeCalories() {
        calories = metricsSummary.calories?.doubleValue
    }

    public func onStartClicked() {
        guard canStart else { return }
        isSessionSaved = false
        isLiveActivityEnded = false
        trackingSessionManager.start(
            startPoint: startPoint,
            activityType: activityType,
            plannedRoute: plannedRoutePoints
        )
        liveActivityController?.start(activityType: activityType.liveActivityKey)
    }

    public func onPauseClicked() {
        trackingSessionManager.pause()
    }

    public func onResumeClicked() {
        trackingSessionManager.resume()
        isLiveActivityEnded = false
        // A session restored after the app was terminated has no Live Activity, and none starts before
        // the user resumes. In a live session one exists and `start` does nothing.
        liveActivityController?.start(activityType: activityType.liveActivityKey)
    }

    public func onStopClicked() {
        // Cancel the observations before `stop()`, so no emission lands mid-teardown.
        observationTasks.forEach { $0.cancel() }
        observationTasks = []

        trackingSessionManager.stop()

        // `stop()` synchronously drives Kotlin's StateFlow to `Finished` before
        // returning, so read its current value directly here rather than relying
        // on the (already-cancelled) `for await` loop above to deliver it.
        trackingState = trackingSessionManager.currentState.value
        recomputeCalories()

        endLiveActivity()
    }

    /// Ends the Live Activity with the final totals of the current (Finished) state, once per session.
    private func endLiveActivity() {
        guard !isLiveActivityEnded else { return }
        isLiveActivityEnded = true
        let finalMetrics = currentMetrics
        liveActivityController?.end(
            distanceMeters: finalMetrics?.distanceMeters ?? 0,
            elapsedMillis: finalMetrics?.elapsedMillis ?? 0,
            currentSpeedMetersPerSecond: finalMetrics?.currentSpeedMetersPerSecond.map { Double(truncating: $0) }
        )
    }

    /// Stop, then remove the stored session: the user does not want it (the Stop button, Stop & Exit and
    /// the Live Activity's Stop). A session that stops by itself at the route's end uses `onStopClicked`
    /// and stays stored until it is saved with Finish. The manager logs a failed clear and discards the
    /// session in memory anyway, so there is nothing more to handle here.
    public func onDiscardClicked() {
        isDiscarding = true
        onStopClicked()
        Task { await clearStoredSession() }
    }

    public func onFinishClicked(snapshotFilePath: String?, onSaved: @escaping () -> Void) {
        guard !isSessionSaved else { return }
        guard case .finished(let data) = onEnum(of: trackingState) else { return }
        let knownUserProfile = loadedUserProfile
        guard knownUserProfile != nil || !isLoadingUserProfile else { return }

        // A restored session has no start time of this instance: the manager holds the stored one. A session
        // stored by an older version has none, so this is an estimate, as on Android.
        let startedAtEpochMillis = trackingSessionManager.sessionDetails.value?.startedAtEpochMillis?.int64Value
            ?? clock.nowMillis() - data.metrics.elapsedMillis
        isSessionSaved = true
        Task {
            do {
                let userProfile: UserProfile?
                if let knownUserProfile {
                    userProfile = knownUserProfile
                } else {
                    userProfile = try await readUserProfileAgain()
                }
                guard let userProfile else {
                    // Nothing is saved or discarded; the user can tap Finish again.
                    isSessionSaved = false
                    emit(.showError(RouteUiErrorGeneral.shared))
                    return
                }
                _ = try await saveActivityUseCase.invoke(
                    activityType: activityType,
                    plannedRoutePoints: plannedRoutePoints,
                    metrics: data.metrics,
                    weightKg: userProfile.weightKg,
                    startedAtEpochMillis: startedAtEpochMillis,
                    snapshotFilePath: snapshotFilePath
                )
                // Only now is the recorded data safe elsewhere; a failed save above keeps the stored session.
                await clearStoredSession()
                onSaved()
            } catch {
                isSessionSaved = false
                emit(.showError(RouteUiErrorGeneral.shared))
            }
        }
    }

    /// The manager's `discard()`: the session is already Finished here, so it only clears, and the clear runs
    /// non-cancellable (the caller, a screen that is left, is often gone by then), as on Android. The manager
    /// logs a failing store and discards in memory; what reaches here is anything else it throws.
    func clearStoredSession() async {
        do {
            try await trackingSessionManager.discard()
        } catch {
            emit(.showError(RouteUiErrorGeneral.shared))
        }
    }

    private func readUserProfileAgain() async throws -> UserProfile? {
        let userProfile = try await userProfileRepository.getUserProfile()
        loadedUserProfile = userProfile
        recomputeCalories()
        return userProfile
    }

    // MARK: - Live Activity

    // The Live Activity's Stop button (a best-effort Darwin notification, only heard while this process is
    // alive) behaves like the in-app Stop. The view's `dismiss` is out of reach here, so it emits
    // `.dismissed` for TrackingView to act on.
    private func handleStopNotification() {
        guard canStop else { return }
        onDiscardClicked()
        emit(.dismissed)
    }
}
