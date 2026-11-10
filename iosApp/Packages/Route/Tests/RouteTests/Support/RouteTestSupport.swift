//
//  RouteTestSupport.swift
//  RouteTests
//
//  Builders shared by the RouteViewModel test classes.
//

import Route
import SharedKit
import TestSupport

/// The scope of the route draft writes of the tests that do not look at the draft. Never cancelled: each
/// saver's collector only waits for its own requests, and the test process ends after the tests.
let unobservedDraftScope = SwiftTestScope()

/// The real keeper and saver over `store`, writing in `scope`.
func makeRouteDraftKeeper(
    store: FakeRouteDraftStore = FakeRouteDraftStore(),
    logger: FakeLogger = FakeLogger(),
    scope: SwiftTestScope = unobservedDraftScope
) -> RouteDraftKeeper {
    RouteDraftKeeper(saver: RouteDraftSaver(store: store, logger: logger, scope: scope))
}

@MainActor
func makeViewModel(
    locationRepository: FakeLocationRepository = FakeLocationRepository(location: RouteFixtures.startPoint),
    directionsRepository: FakeDirectionsRepository = FakeDirectionsRepository(route: RouteFixtures.route),
    userProfileRepository: FakeUserProfileRepository = FakeUserProfileRepository(),
    routeDraftKeeper: RouteDraftKeeper = makeRouteDraftKeeper()
) -> RouteViewModel {
    RouteViewModel(
        getCurrentLocationUseCase: GetCurrentLocationUseCase(locationRepository: locationRepository),
        generateClosedRouteUseCase: GenerateClosedRouteUseCase(directionsRepository: directionsRepository),
        userProfileRepository: userProfileRepository,
        routeDraftKeeper: routeDraftKeeper
    )
}

/// A ViewModel with its start point loaded, three waypoints tapped and a generated route.
@MainActor
func makeViewModelWithGeneratedRoute(
    locationRepository: FakeLocationRepository = FakeLocationRepository(location: RouteFixtures.startPoint),
    userProfileRepository: FakeUserProfileRepository = FakeUserProfileRepository()
) async -> RouteViewModel {
    let viewModel = makeViewModel(
        locationRepository: locationRepository,
        userProfileRepository: userProfileRepository
    )
    await waitUntil { viewModel.startPoint != nil }
    tapWaypoints(3, on: viewModel)
    viewModel.onGenerateRouteClicked()
    await waitUntil { viewModel.generatedRoute != nil }
    return viewModel
}

@MainActor
func tapWaypoints(_ count: Int, on viewModel: RouteViewModel) {
    for index in 0..<count {
        viewModel.onMapTapped(RouteFixtures.waypoint(index))
    }
}

extension RouteUiEvent {
    var shownError: (any RouteUiError)? {
        guard case .showError(let error) = self else { return nil }
        return error
    }
}
