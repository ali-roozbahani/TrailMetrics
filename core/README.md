# core

KMP module, **`commonMain` only** — no `androidMain`, no `iosMain`. Targets:
`android`, `iosArm64`, `iosSimulatorArm64` (build targets for export
purposes; there is no platform-specific source in this module).

This module used to also hold Android Compose design-system and Google Maps
code. That code was split out into `androidApp/core-ui` after discovering
that the Compose compiler Gradle plugin instruments *every* Kotlin
compilation in a module — including iOS targets — so any Compose code here
broke iOS builds even with zero `@Composable` usage on that target. See
`docs/architecture/ADR-003-core-ui-split.md` for the full story.

## What lives here

- **`navigation/AppRoute.kt`**: the single source of truth for what screens
  exist in the app and what data they carry. A plain `@Serializable` sealed
  interface — no dependency on `androidx.navigation` or `SwiftUI`'s
  `NavigationPath`. Android wires this into Navigation Compose's type-safe
  `composable<T>()`; iOS is expected to consume it (via SKIE, exported as a
  Swift enum) with `NavigationStack`.
- **`error/RouteUiError.kt`**: a platform-agnostic classification of a
  `domain.RouteError` for UI purposes (`LocationUnavailable`,
  `MissingLocationPermission`, `General`) plus the `RouteError?.toUiError()`
  mapping function. This is the *classification*, not the *presentation* —
  no string resources, no `NSLocalizedString`, no UI framework type.

## What does NOT belong here

- Anything importing `androidx.compose.*` — see `androidApp/core-ui` for
  Android Compose design-system code.
- Anything importing `android.*` platform APIs directly (`Bundle`, `NavType`,
  etc.) — those belong in `androidApp/app` if they're navigation-adjacent,
  or `androidApp/core-ui` otherwise.
- String resource IDs, `NSLocalizedString` keys, or any other
  presentation-layer concern. Mapping a `RouteUiError` to displayable text
  is a platform-specific extension (see `androidApp/core-ui`'s
  `RouteUiErrorAndroid.kt` for the Android side; iOS should do the
  equivalent in Swift).

## Dependencies

`core` depends on `domain` only.

## Extending this module

Before adding anything here, ask: "does this need to exist identically on
both Android and iOS, with zero UI framework dependency?" If the answer
involves any UI toolkit at all — even indirectly — it doesn't belong in
`core`. Raw design tokens (hex color ints, spacing/font-size numbers as
plain `Int`/`Float`) would qualify if they're ever added; a `Color` or
`TextStyle` object never would.
