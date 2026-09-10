# domain

Pure Kotlin business logic. Zero Android or iOS dependency — this module
must compile and pass tests without ever touching `android.*`, `androidx.*`,
Compose, or any platform framework.

## What lives here

- **Models** (`model/`): `ActivityRecord`, `ActivityType`, `Coordinates`,
  `Route`, `RouteError`, `TrackingState`, `TrackingMetrics`, `UserProfile`,
  etc. Plain data classes / sealed interfaces, `@Serializable` where they
  cross a navigation or persistence boundary.
- **Repository interfaces** (`repository/`): contracts implemented by `data`
  (`ActivityHistoryRepository`, `UserProfileRepository`, `LocationRepository`,
  `DirectionsRepository`). `domain` never implements these — only declares
  the contract.
- **Use cases** (`usecase/`): single-purpose orchestration classes
  (`GetCurrentLocationUseCase`, `GenerateClosedRouteUseCase`,
  `SaveActivityUseCase`). A use case exists when it combines more than one
  repository call or applies business rules on top of a raw repository
  method — a thin passthrough to a single repository call is usually not
  worth a use case.
- **Tracking orchestration** (`tracking/`): `TrackingSessionManager`, the
  state machine driving Start/Pause/Resume/Stop.
- **Utilities** (`util/`): `CalorieCalculator`, `Clock` (injectable time
  source for testability).

## What does NOT belong here

- Anything importing `android.*`, `androidx.*`, `UIKit`, or any Compose/
  SwiftUI type.
- Repository *implementations* (those live in `data`).
- Anything related to navigation, string resources, or UI state shaping
  (those live in `core` or the feature modules).

## Dependencies

`domain` depends on nothing else in this repo. It is a leaf module that
everything else (`data`, `core`, `shared`, all feature modules) depends on.

## Testing

`commonTest` uses `kotlin.test` and hand-written fakes (see
`domain/src/commonTest/.../fakes/`) — no MockK, no JUnit, no Robolectric.
Kotlin/Native has no reflection, so reflection-based mocking libraries
cannot run here. Write a fake implementing the interface directly instead
of reaching for a mocking framework.

## Extending this module

Adding a new use case or model: put it in the matching subpackage, keep it
framework-free, and write a `commonTest` alongside it. If you're unsure
whether something belongs in `domain` vs `core` vs `data`, the test is:
"would this concept exist in a version of this app with a completely
different UI and a completely different backend?" If yes, it's `domain`.
