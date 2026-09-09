# core / commonMain

Platform-agnostic, pure Kotlin code shared between Android and iOS.

Belongs here:
- Navigation route models (`AppRoute`) — plain sealed interfaces/data
  classes, no platform navigation framework dependency
- UI error/state models that both platforms need to react to
  (`RouteUiError`) — the *classification* of an error, not its
  presentation (no string resources, no platform UI types)
- Any future design tokens expressed as raw values (hex color ints,
  spacing/font-size numbers) — NOT Compose `Color`/`TextStyle` objects

Does NOT belong here:
- Anything importing `androidx.compose.*` — Compose Multiplatform is a
  deliberate non-goal for this project (see ADR in docs/)
- Anything importing `androidx.navigation.*`, `android.os.*`, or other
  Android-only APIs
- Actual UI components/screens — those are native per-platform
  (Jetpack Compose for Android, SwiftUI for iOS)
