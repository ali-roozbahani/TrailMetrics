//
//  RouteViewModel.swift
//  Route
//

import Foundation
import SharedKit

@MainActor
public class RouteViewModel: ObservableObject {
    private static let minWaypoints = 3

    @Published public var startPoint: Coordinates?
    @Published public var waypoints: [RoutePoint] = []
    @Published public var generatedRoute: Route?
    @Published public var userProfile: UserProfile?
    @Published public var selectedActivityType: ActivityType = .running
    @Published public var isLoading = false

    public var canGenerateRoute: Bool {
        startPoint != nil && waypoints.count >= Self.minWaypoints && !isLoading
    }

    // Not a stored `let events` created once in init(): AsyncStream supports only one
    // live consumer over its lifetime. RouteView's `.task` consuming this is cancelled
    // whenever a pushed screen (e.g. Tracking) covers it, and gets a brand-new `Task`
    // when that screen pops and RouteView is revealed again — but a second `for await`
    // over an AsyncStream whose first consumer was cancelled (rather than the stream
    // finishing on its own) exits immediately without ever receiving anything, silently.
    // Exposing a factory instead lets each fresh `.task` get its own fresh stream.
    private var eventsContinuation: AsyncStream<RouteUiEvent>.Continuation?

    private let getCurrentLocationUseCase: GetCurrentLocationUseCase
    private let generateClosedRouteUseCase: GenerateClosedRouteUseCase
    private let userProfileRepository: UserProfileRepository

    public init(
        getCurrentLocationUseCase: GetCurrentLocationUseCase = KoinHelper().getCurrentLocationUseCase(),
        generateClosedRouteUseCase: GenerateClosedRouteUseCase = KoinHelper().generateClosedRouteUseCase(),
        userProfileRepository: UserProfileRepository = KoinHelper().userProfileRepository()
    ) {
        self.getCurrentLocationUseCase = getCurrentLocationUseCase
        self.generateClosedRouteUseCase = generateClosedRouteUseCase
        self.userProfileRepository = userProfileRepository

        loadCurrentLocation()
        getAndUpdateUserProfile()
    }

    public func makeEventsStream() -> AsyncStream<RouteUiEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: RouteUiEvent.self)
        eventsContinuation = continuation
        return stream
    }

    private func emit(_ event: RouteUiEvent) {
        eventsContinuation?.yield(event)
    }

    private func loadCurrentLocation() {
        Task {
            do {
                startPoint = try await getCurrentLocationUseCase.invoke()
            } catch {
                emit(.showError(error.underlyingRouteError?.toUiError() ?? RouteUiErrorGeneral.shared))
            }
        }
    }

    public func onMapTapped(_ coordinates: Coordinates) {
        let waypoint = RoutePoint(coordinates: coordinates, order: Int32(waypoints.count))
        waypoints.append(waypoint)
    }

    public func onGenerateRouteClicked() {
        guard let startPoint else { return }

        isLoading = true

        let draft = RouteDraft(
            startPoint: RoutePoint(coordinates: startPoint, order: 0),
            waypoints: waypoints
        )

        Task {
            do {
                generatedRoute = try await generateClosedRouteUseCase.invoke(draft: draft)
                isLoading = false
            } catch {
                isLoading = false
                emit(.showError(error.underlyingRouteError?.toUiError() ?? RouteUiErrorGeneral.shared))
            }
        }
    }

    public func onResetClicked() {
        startPoint = nil
        waypoints = []
        generatedRoute = nil
        userProfile = nil
        selectedActivityType = .running
        isLoading = false
        loadCurrentLocation()
    }

    public func onWaypointRemoved(_ removeCandidate: RoutePoint) {
        let updatedWaypoints = waypoints
            .filter { $0 != removeCandidate }
            .enumerated()
            .map { index, point in RoutePoint(coordinates: point.coordinates, order: Int32(index)) }

        waypoints = updatedWaypoints
        generatedRoute = nil
    }

    public func onActivityTypeSelected(_ activityType: ActivityType) {
        selectedActivityType = activityType
    }

    public func saveUserProfile(weightKg: Double) {
        Task {
            let profile = UserProfile(weightKg: weightKg)
            try await userProfileRepository.saveUserProfile(userProfile: profile)
            userProfile = profile
        }
    }

    public func onStartTrackingClicked() {
        Task {
            guard try await userProfileRepository.getUserProfile() != nil else {
                emit(.requestUserProfile)
                return
            }

            guard let startPoint, let generatedRoute, !generatedRoute.points.isEmpty else {
                return
            }

            emit(
                .navigateToTracking(
                    startPoint: startPoint,
                    plannedRoutePoints: generatedRoute.points.map { $0.coordinates },
                    activityType: selectedActivityType
                )
            )
        }
    }

    private func getAndUpdateUserProfile() {
        Task {
            userProfile = try await userProfileRepository.getUserProfile()
        }
    }
}

private extension Error {
    /// SKIE bridges a thrown Kotlin exception to an NSError with the real value in userInfo["KotlinException"].
    var underlyingRouteError: RouteError? {
        guard let nsError = self as? NSError,
              let kotlinException = nsError.userInfo["KotlinException"] else {
            return nil
        }
        return kotlinException as? RouteError
    }
}
