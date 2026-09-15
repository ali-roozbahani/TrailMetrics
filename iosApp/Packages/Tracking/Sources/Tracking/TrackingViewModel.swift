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
    private var eventsContinuation: AsyncStream<TrackingUiEvent>.Continuation?

    private let trackingSessionManager: TrackingSessionManager
    private let userProfileRepository: UserProfileRepository
    private let calorieCalculator: CalorieCalculator
    private let saveActivityUseCase: SaveActivityUseCase
    private let clock: Clock

    private var loadedUserProfile: UserProfile?
    private var startedAtEpochMillis: Int64 = 0

    // Kotlin's `trackingScope` runs on `Dispatchers.Default`, and the KMP bridge's
    // continuation-resume does not guarantee a MainActor hop back into this
    // @MainActor class — so `for await` resumption after a Flow emission can land on
    // a background thread despite that annotation. These are stored (rather than
    // fire-and-forget) so `onStopClicked()` can cancel them deterministically instead
    // of relying solely on `[weak self]` unwinding whenever the instance happens to
    // deallocate.
    private var stateObservationTask: Task<Void, Never>?
    private var locationIssuesObservationTask: Task<Void, Never>?

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

    public var currentMetrics: TrackingMetrics? {
        switch onEnum(of: trackingState) {
        case .tracking(let data): return data.metrics
        case .paused(let data): return data.metrics
        default: return nil
        }
    }

    public init(
        activityType: ActivityType,
        plannedRoutePoints: [Coordinates],
        startPoint: Coordinates,
        trackingSessionManager: TrackingSessionManager = KoinHelper().trackingSessionManager(),
        userProfileRepository: UserProfileRepository = KoinHelper().userProfileRepository(),
        calorieCalculator: CalorieCalculator = KoinHelper().calorieCalculator(),
        saveActivityUseCase: SaveActivityUseCase = KoinHelper().saveActivityUseCase(),
        clock: Clock = KoinHelper().clock()
    ) {
        self.activityType = activityType
        self.plannedRoutePoints = plannedRoutePoints
        self.startPoint = startPoint
        self.trackingSessionManager = trackingSessionManager
        self.userProfileRepository = userProfileRepository
        self.calorieCalculator = calorieCalculator
        self.saveActivityUseCase = saveActivityUseCase
        self.clock = clock

        loadUserProfile()
        observeTrackingState()
        observeLocationIssues()
    }

    public func makeEventsStream() -> AsyncStream<TrackingUiEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: TrackingUiEvent.self)
        eventsContinuation = continuation
        return stream
    }

    private func emit(_ event: TrackingUiEvent) {
        eventsContinuation?.yield(event)
    }

    private func loadUserProfile() {
        Task {
            loadedUserProfile = try await userProfileRepository.getUserProfile()
            recomputeCalories()
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
        startedAtEpochMillis = clock.nowMillis()
        trackingSessionManager.start(startPoint: startPoint)
    }

    public func onPauseClicked() {
        trackingSessionManager.pause()
    }

    public func onResumeClicked() {
        trackingSessionManager.resume()
    }

    public func onStopClicked() {
        trackingSessionManager.stop()

        // `stop()` synchronously drives Kotlin's StateFlow to `Finished` before
        // returning, so read its current value directly here rather than waiting for
        // that emission to arrive via the (now about-to-be-cancelled) `for await`
        // loop above — this is the one update `stateObservationTask` would otherwise
        // need to still be alive to deliver, and capturing it synchronously means
        // cancelling immediately below can't lose it or race with it.
        trackingState = trackingSessionManager.currentState.value
        recomputeCalories()

        // No further emission should be allowed to land mid-teardown once Stop has
        // been pressed — cancel deterministically here rather than relying solely on
        // `[weak self]` unwinding whenever this instance happens to deallocate.
        stateObservationTask?.cancel()
        locationIssuesObservationTask?.cancel()
        stateObservationTask = nil
        locationIssuesObservationTask = nil
    }

    public func onFinishClicked(snapshotFilePath: String?, onSaved: @escaping () -> Void) {
        guard case .finished(let data) = onEnum(of: trackingState) else { return }
        guard let userProfile = loadedUserProfile else { return }

        Task {
            do {
                _ = try await saveActivityUseCase.invoke(
                    activityType: activityType,
                    plannedRoutePoints: plannedRoutePoints,
                    metrics: data.metrics,
                    weightKg: userProfile.weightKg,
                    startedAtEpochMillis: startedAtEpochMillis,
                    snapshotFilePath: snapshotFilePath
                )
                onSaved()
            } catch {
                emit(.showError(RouteUiErrorGeneral.shared))
            }
        }
    }
}
