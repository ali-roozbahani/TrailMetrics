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
    /// True while the app reads the stored session (`SavedSessionOfferModel.isRestoring`): Start is not
    /// offered and `onStartClicked()` does nothing until it is false.
    @Published public private(set) var isRestoring: Bool

    public let activityType: ActivityType
    public let plannedRoutePoints: [Coordinates]
    public let startPoint: Coordinates

    // Not a stored `let events` created once in init(): AsyncStream supports only one
    // live consumer over its lifetime. TrackingView doesn't currently get covered by a
    // further push in this app's navigation structure, so this hasn't manifested here
    // yet — but it shares the identical pattern that broke RouteView's event delivery
    // after being covered and revealed once (see RouteViewModel.makeEventsStream()),
    // so it's fixed the same way pre-emptively rather than leaving a matching latent
    // bug for whenever something is later pushed on top of Tracking.
    //
    // Before TrackingView's first `.task` runs nobody consumes, and the profile load started
    // in init() can fail by then. An event emitted while no consumer is active goes to
    // `pendingEvents` and the next stream delivers it first, as in RouteViewModel.
    private var eventsContinuation: AsyncStream<TrackingUiEvent>.Continuation?
    /// Events emitted while no consumer was active, oldest first, at most `maxPendingEvents`.
    private var pendingEvents: [TrackingUiEvent] = []
    /// Location issues can repeat while nobody consumes; TrackingView shows one error at a time.
    private static let maxPendingEvents = 10

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

    // Kotlin's `trackingScope` runs on `Dispatchers.Default`, and the KMP bridge's
    // continuation-resume does not guarantee a MainActor hop back into this
    // @MainActor class — so `for await` resumption after a Flow emission can land on
    // a background thread despite that annotation. These are stored (rather than
    // fire-and-forget) so `onStopClicked()` can cancel them deterministically instead
    // of relying solely on `[weak self]` unwinding whenever the instance happens to
    // deallocate.
    private var stateObservationTask: Task<Void, Never>?
    private var locationIssuesObservationTask: Task<Void, Never>?

    private var liveActivityController: TrackingLiveActivityController?

    public var canStart: Bool {
        switch onEnum(of: trackingState) {
        case .idle, .finished: return true
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

    public var canResume: Bool {
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

    public init(
        activityType: ActivityType,
        plannedRoutePoints: [Coordinates],
        startPoint: Coordinates,
        isRestoring: Bool = false,
        trackingSessionManager: TrackingSessionManager = KoinHelper().trackingSessionManager(),
        userProfileRepository: UserProfileRepository = KoinHelper().userProfileRepository(),
        calorieCalculator: CalorieCalculator = KoinHelper().calorieCalculator(),
        saveActivityUseCase: SaveActivityUseCase = KoinHelper().saveActivityUseCase(),
        clock: Clock = KoinHelper().clock()
    ) {
        self.activityType = activityType
        self.plannedRoutePoints = plannedRoutePoints
        self.startPoint = startPoint
        self.isRestoring = isRestoring
        self.trackingSessionManager = trackingSessionManager
        self.userProfileRepository = userProfileRepository
        self.calorieCalculator = calorieCalculator
        self.saveActivityUseCase = saveActivityUseCase
        self.clock = clock

        loadUserProfile()
        observeTrackingState()
        observeLocationIssues()

        liveActivityController = TrackingLiveActivityController { [weak self] in
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
                                .map { Double(truncating: $0) }
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

    public func onRestoringChanged(_ isRestoring: Bool) {
        self.isRestoring = isRestoring
    }

    public func onStartClicked() {
        isSessionSaved = false
        trackingSessionManager.start(startPoint: startPoint, activityType: activityType)
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
        // No further emission should be allowed to land mid-teardown once Stop has
        // been pressed — cancel deterministically here, before `stop()` below,
        // rather than relying solely on `[weak self]` unwinding whenever this
        // instance happens to deallocate. (`onStopClicked()` has no `await` in its
        // own body, and MainActor's serial execution means nothing else queued on
        // it can interleave mid-call regardless — so this ordering doesn't change
        // behavior, it just matches the intent described above.)
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

    // Called by TrackingLiveActivityController when the Live Activity's Stop
    // button posts its Darwin notification (best-effort — only reaches this
    // app process if it's still alive; see TrackingLiveActivityController).
    //
    // Unlike the in-app Stop button (TrackingView's controlsRow/exit alert),
    // which calls `dismiss()` directly at its own call site right after
    // `onStopClicked()`, this path has no access to the View's `dismiss`
    // environment value — so it emits `.dismissed` for TrackingView to act
    // on instead, producing the same end result (per product decision:
    // Live Activity Stop should behave exactly like the in-app Stop button).
    private func handleStopNotification() {
        guard canStop else { return }
        onDiscardClicked()
        emit(.dismissed)
    }
}
