# androidApp/core-ui

Plain Android library module (**not** KMP). Holds every piece of shared
Compose UI that would otherwise be duplicated across `androidApp/feature-*`.

This module exists separately from the KMP `core` module because the
Compose compiler Gradle plugin instruments every Kotlin compilation in a
module it's applied to, including iOS targets — so Compose code cannot live
inside a KMP module that also targets iOS, even in `androidMain`, without
breaking the iOS build. See `docs/architecture/ADR-003-core-ui-split.md`.

## What lives here

- **`designsystem/theme/`**: `Color.kt`, `Theme.kt` (`TrailMetricsTheme`),
  `Type.kt` — the Material3 color scheme and typography.
- **`designsystem/component/`**: `MetricCell.kt` and other small, reusable
  Composables shared across two or more feature modules. A Composable used
  by only one feature stays in that feature module — it only moves here
  once a second feature needs it.
- **`map/`**: Google Maps Compose components — `TrailGoogleMap`,
  `RoutePolyline`, `CurrentLocationMarker`, `StartFinishMarker`. These wrap
  `com.google.maps.android.compose`, which has no iOS equivalent (iOS map
  UI is implemented natively in Swift, in the relevant `iosApp/Packages/*`
  package).
- **`error/RouteUiErrorAndroid.kt`**: the `RouteUiError.stringRes: Int`
  extension mapping `core`'s platform-agnostic error classification to an
  Android `@StringRes` id.
- **`res/values/strings.xml`**: the string resources those mappings point
  to.

## What does NOT belong here

- Anything that has no UI framework dependency — that belongs in the KMP
  `core` module instead, so iOS can share it too.
- Feature-specific screens (`RouteScreen`, `TrackingScreen`, `HistoryScreen`)
  — those stay in their own `androidApp/feature-*` module.

## Dependencies

`core-ui` depends on `core` (for `RouteUiError`) and `domain` (for
`Coordinates` and other models used by map composables).

## Extending this module

Before adding a Composable here, check whether it's actually shared by two
or more feature modules yet. Premature extraction adds an extra module
hop for no benefit — keep new UI local to its feature until a second
consumer shows up.
