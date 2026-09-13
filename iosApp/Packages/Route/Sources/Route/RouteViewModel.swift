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

    public let events: AsyncStream<RouteUiEvent>
    private let eventsContinuation: AsyncStream<RouteUiEvent>.Continuation

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

        let (stream, continuation) = AsyncStream.makeStream(of: RouteUiEvent.self)
        self.events = stream
        self.eventsContinuation = continuation

        loadCurrentLocation()
        getAndUpdateUserProfile()
    }

    private func emit(_ event: RouteUiEvent) {
        eventsContinuation.yield(event)
    }

    private func loadCurrentLocation() {
        Task {
            do {
                // GetCurrentLocationUseCase.invoke() returns `Result<Coordinates>` in Kotlin; SKIE
                // unwraps that to `async throws -> Any?` (the generic success type is erased at the
                // Result<T> ABI boundary), so the success value needs a runtime cast back to Coordinates.
                guard let coordinates = try await getCurrentLocationUseCase.invoke() as? Coordinates else {
                    return
                }
                startPoint = coordinates
            } catch {
                emit(.showError((error as? RouteError)?.toUiError() ?? RouteUiErrorGeneral.shared))
                if error is RouteError.MissingLocationPermission {
                    emit(.requestLocationPermission)
                }
            }
        }
    }

    public func onLocationPermissionGranted() {
        loadCurrentLocation()
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
                guard let route = try await generateClosedRouteUseCase.invoke(draft: draft) as? Route else {
                    isLoading = false
                    return
                }
                generatedRoute = route
                isLoading = false
            } catch {
                isLoading = false
                emit(.showError((error as? RouteError)?.toUiError() ?? RouteUiErrorGeneral.shared))
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
