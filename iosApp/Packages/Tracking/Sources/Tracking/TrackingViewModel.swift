//
//  TrackingViewModel.swift
//  Tracking
//

import Foundation
import SharedKit

@MainActor
public class TrackingViewModel: ObservableObject {
    @Published public private(set) var trackingState: TrackingState = TrackingStateIdle.shared
    @Published public private(set) var calories: Double?
    /// Set when the user discards the session (Stop, Stop & Exit): the screen is on its way out.
    @Published public private(set) var isDiscarding = false

    public let activityType: ActivityType
    public let plannedRoutePoints: [Coordinates]
    public let startPoint: Coordinates

    // Not a stored `let events` created once in init(): an AsyncStream has one consumer for its whole
    // life, so a screen covered by a push would leave it dead (see RouteViewModel.makeEventsStream()).
    //
    // Before TrackingView's first `.task` runs nobody consumes, and the profile load started
    // in init() can fail by then. An event emitted while no consumer is active goes to
    // `pendingEvents` and the next stream delivers it first, as in RouteViewModel.
    private var eventsContinuation: AsyncStream<TrackingUiEvent>.Continuation?
    /// Events emitted while no consumer was active, oldest first, at most `maxPendingEvents`.
    private var pendingEvents: [TrackingUiEvent] = []
    /// Location issues can repeat while nobody consumes; TrackingView shows one error at a time.
    private static let maxPendingEvents = 10

    /// The one source of "the app is still reading the stored session" (`isRestoring`): `canStart` and
    /// `onStartClicked()` read it here, nothing is copied, so a caller cannot skip the gate.
    private let storedSessionReadState: any StoredSessionReadState
    private let trackingSessionManager: TrackingSessionManager
    private let userProfileRepository: UserProfileRepository
    private let calorieCalculator: CalorieCalculator
    private let saveActivityUseCase: SaveActivityUseCase
    private let clock: Clock

    private var loadedUserProfile: UserProfile?
    /// True while the load started in `init` runs; a Finish in that time does nothing.
    private var isLoadingUserProfile = false
    /// Set before a save starts, so a repeated Finish neither saves twice nor calls `onSaved`
    /// twice; cleared when the save fails (retry) and when a new session starts.
    private var isSessionSaved = false

    // Kotlin's `trackingScope` runs on `Dispatchers.Default`, so `for await` can resume off the main actor
    // despite @MainActor. The tasks are stored so `onStopClicked()` cancels them deterministically.
    private var stateObservationTask: Task<Void, Never>?
    private var locationIssuesObservationTask: Task<Void, Never>?

    private var liveActivityController: TrackingLiveActivityController?

    public var canStart: Bool {
        switch onEnum(of: trackingState) {
        case .idle, .finished: return !storedSessionReadState.isRestoring
        case .tracking, .paused: return false
        }
    }

    public var canPause: Bool {
        if case .tracking = onEnum(of: trackingState) { return true }
        return false
    }

    /// A Finished session waits to be saved: the route's end, or a restored one. Not while it is discarded.
    public var canFinish: Bool {
        if case .finished = onEnum(of: trackingState) { return !isDiscarding }
        return false
    }

    public var canResume: Bool { isPaused }

    private var isPaused: Bool {
        if case .paused = onEnum(of: trackingState) { return true }
        return false
    }

    public var canStop: Bool {
        switch onEnum(of: trackingState) {
        case .tracking, .paused: return true
        default: return false
        }
    }

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

    /// The numbers the metrics panel shows: in every state that has a session, Finished included, so the panel
    /// stays above the Finish card after Stop and after a restore of a Finished session (as on Android).
    public var currentMetrics: TrackingMetrics? {
        switch onEnum(of: trackingState) {
        case .tracking(let data): return data.metrics
        case .paused(let data): return data.metrics
        case .finished(let data): return data.metrics
        case .idle: return nil
        }
    }

    public convenience init(
        activityType: ActivityType,
        plannedRoutePoints: [Coordinates],
        startPoint: Coordinates,
        storedSessionReadState: any StoredSessionReadState,
        trackingSessionManager: TrackingSessionManager = KoinHelper().trackingSessionManager(),
        userProfileRepository: UserProfileRepository = KoinHelper().userProfileRepository(),
        calorieCalculator: CalorieCalculator = KoinHelper().calorieCalculator(),
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
            calorieCalculator: calorieCalculator,
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
        calorieCalculator: CalorieCalculator,
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
        self.calorieCalculator = calorieCalculator
        self.saveActivityUseCase = saveActivityUseCase
        self.clock = clock

        loadUserProfile()
        observeTrackingState()
        observeLocationIssues()

        liveActivityController = TrackingLiveActivityController(client: liveActivityClient) { [weak self] in
            self?.handleStopNotification()
        }
    }

    public func makeEventsStream() -> AsyncStream<TrackingUiEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: TrackingUiEvent.self)
        for event in pendingEvents {
            continuation.yield(event)
        }
        pendingEvents.removeAll()
        eventsContinuation = continuation
        return stream
    }

    private func emit(_ event: TrackingUiEvent) {
        if case .enqueued = eventsContinuation?.yield(event) { return }
        pendingEvents.append(event)
        if pendingEvents.count > Self.maxPendingEvents {
            pendingEvents.removeFirst()
        }
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
        stateObservationTask = Task { [weak self] in
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
                }
            }
        }
    }

    private func observeLocationIssues() {
        locationIssuesObservationTask = Task { [weak self] in
            guard let flow = self?.trackingSessionManager.locationIssues else { return }
            for await issue in flow {
                guard let self else { return }
                await MainActor.run {
                    self.emit(.showError(issue.toUiError()))
                }
            }
        }
    }

    deinit {
        stateObservationTask?.cancel()
        locationIssuesObservationTask?.cancel()
    }

    private func recomputeCalories() {
        guard let metrics = currentMetrics,
              let userProfile = loadedUserProfile,
              let averageSpeed = metrics.averageSpeedMetersPerSecond?.floatValue else {
            calories = nil
            return
        }
        calories = calorieCalculator.calculate(
            activityType: activityType,
            averageSpeedMetersPerSecond: averageSpeed,
            weightKg: userProfile.weightKg,
            durationMillis: metrics.elapsedMillis
        )
    }

    public func onStartClicked() {
        guard !storedSessionReadState.isRestoring else { return }
        isSessionSaved = false
        trackingSessionManager.start(
            startPoint: startPoint,
            activityType: activityType,
            plannedRoute: plannedRoutePoints
        )
        liveActivityController?.start(activityType: liveActivityTypeKey)
    }

    public func onPauseClicked() {
        trackingSessionManager.pause()
    }

    public func onResumeClicked() {
        trackingSessionManager.resume()
        // A session restored after the app was terminated has no Live Activity, and none starts before
        // the user resumes. In a live session one exists and `start` does nothing.
        liveActivityController?.start(activityType: liveActivityTypeKey)
    }

    public func onStopClicked() {
        // Cancel the observations before `stop()`, so no emission lands mid-teardown.
        stateObservationTask?.cancel()
        locationIssuesObservationTask?.cancel()
        stateObservationTask = nil
        locationIssuesObservationTask = nil

        trackingSessionManager.stop()

        // `stop()` synchronously drives Kotlin's StateFlow to `Finished` before
        // returning, so read its current value directly here rather than relying
        // on the (already-cancelled) `for await` loop above to deliver it.
        trackingState = trackingSessionManager.currentState.value
        recomputeCalories()

        // `trackingState` was just advanced to `.finished` above, so the Live Activity's last-shown content
        // reflects the session's actual final distance/time.
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
    private func clearStoredSession() async {
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

    // Not shown from here: the Live Activity attribute carries this English name as a stable key,
    // and the widget extension localizes it with its own catalog (TrackingLiveActivity.swift).
    private var liveActivityTypeKey: String {
        switch activityType {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        }
    }

    // The Live Activity's Stop button (a best-effort Darwin notification, only heard while this process is
    // alive) behaves like the in-app Stop. The view's `dismiss` is out of reach here, so it emits
    // `.dismissed` for TrackingView to act on.
    private func handleStopNotification() {
        guard canStop else { return }
        onDiscardClicked()
        emit(.dismissed)
    }
}
