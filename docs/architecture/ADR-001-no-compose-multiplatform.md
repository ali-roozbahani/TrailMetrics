# ADR-001: No Compose Multiplatform — native UI per platform

## Status
Accepted.

## Context
Kotlin Multiplatform supports sharing UI code across Android and iOS via
Compose Multiplatform, which would let Jetpack Compose screens run
unmodified on iOS. The alternative is writing SwiftUI natively for iOS
while keeping Jetpack Compose on Android, sharing only the layers below UI
(domain, data, navigation identity).

## Decision
This project uses native UI per platform: Jetpack Compose on Android,
SwiftUI on iOS. Compose Multiplatform is explicitly not adopted.

## Reasoning
- **Portfolio and learning goals**: the project exists partly to
  demonstrate KMP architecture skills for interviews, and partly to learn
  SwiftUI and iOS-native patterns directly, not through a Compose
  abstraction layer.
- **iOS platform idiom**: SwiftUI integrates with iOS-specific APIs
  (`NavigationStack`, `.task`, platform share sheets, widgets, etc.) more
  directly than a cross-compiled Compose UI layer would.
- **Compose compiler plugin scope**: in practice, the Compose compiler
  Gradle plugin instruments every Kotlin compilation in a module once
  applied — including non-Android targets — which caused real build
  failures during this project (see ADR-003) even for Android-only Compose
  usage inside a KMP module. Fully embracing Compose Multiplatform would
  require a different, more invasive Gradle setup across the whole module
  graph; staying native avoids this class of problem entirely.

## Consequences
- Every feature (Route, Tracking, History, ...) is implemented twice at
  the UI layer: once in Jetpack Compose (`androidApp/feature-*`), once in
  SwiftUI (`iosApp/Packages/<Feature>`).
- Shared code stops at `domain`/`data`/`core`/`shared` — `AppRoute`,
  repository interfaces, and Koin wiring are shared; screens, ViewModels'
  concrete implementation, and design-system components are not.
- iOS ViewModels are native `ObservableObject` classes rather than shared
  KMP `ViewModel`s — see `docs/architecture/OVERVIEW.md`.
