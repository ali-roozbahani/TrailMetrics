# iOS developer guide

Read `docs/coding-standards/shared_conventions.md` first — this document
only covers rules specific to the Swift/SwiftUI side.

## Architecture

- One local Swift Package per feature under `iosApp/Packages/<Feature>/`,
  mirroring `androidApp/feature-<name>`. Every feature package depends on
  `SharedKit` (never directly on the `TrailMetricsShared.xcframework` — see
  `docs/architecture/OVERVIEW.md`).
- `@MainActor class <Feature>ViewModel: ObservableObject` with `@Published`
  properties, mirroring the Android `ViewModel`'s `StateFlow<UiState>` —
  but implemented natively in Swift, not shared via KMP. See
  `docs/architecture/ADR-001-no-compose-multiplatform.md` for why.
- ViewModels resolve their dependencies from Koin via `shared`'s
  `KoinHelper` (`iosApp/Packages/SharedKit`), with a default-parameter
  constructor (`init(repository: X = KoinHelper().getX())`) so previews and
  tests can inject a fake.
- Kotlin `Flow` properties are consumed with `for await` (SKIE converts them
  to `AsyncSequence`) inside a `.task { }` modifier, not
  `.onAppear`/`.onDisappear` pairs.
- `AppRoute` (from `SharedKit`, exported by SKIE as a Swift enum) is the
  single source of truth for navigation destinations — do not define a
  parallel Swift-only route enum.

## SwiftUI

- Views are structs; keep them free of business logic — a View reads
  `@Published` state and calls ViewModel methods, it doesn't compute
  derived state inline beyond trivial formatting.
- Prefer `NavigationStack(path:)` with `AppRoute` values over manual
  `NavigationLink(destination:)` wiring, once more than one feature package
  needs to participate in the same navigation flow.
- New reusable SwiftUI components used by 2+ features go in a shared
  package (create one, e.g. `iosApp/Packages/DesignSystem`, the first time
  this need arises — none exists yet, don't build ahead of need).

## Composition root

- `TrailMetricsApp.init()` is the only place `KoinInitIosKt.doInitKoinIos()`
  is called — never call it from a View's `init()` (SwiftUI may re-run a
  View's initializer, which would attempt to start Koin twice and crash).

## Build integration

- After changing `domain`, `data`, `core`, or `shared` Kotlin source, the
  XCFramework must reflect it before Xcode sees the change. The project's
  "Build KMP Shared Framework" Run Script phase does this automatically
  (hash-based, skips the Gradle invocation when nothing changed) — see
  `docs/architecture/OVERVIEW.md`. Don't disable or bypass this phase.

## Enforcement (SwiftLint)

Config: `iosApp/.swiftlint.yml`, run via `swiftlint lint --strict` (also in
CI, macOS job — see `ci.yml`). Key rules beyond SwiftLint's defaults:

```yaml
opt_in_rules:
  - force_unwrapping
  - unused_import
  - explicit_init

disabled_rules:
  - todo

force_unwrapping: error
force_cast: error
force_try: error

identifier_name:
  min_length: 3
  excluded: [id]

line_length:
  warning: 120
  error: 160
```

- `force_unwrapping`/`force_cast`/`force_try` are **errors**, not warnings —
  a force-unwrap (`!`) is treated the same as a deprecated API on the
  Android side: something to restructure around, not silence. Use
  `guard let`/`if let`, or `as?` with explicit `else` handling.
- SwiftLint has no direct "no deprecated API" rule; Swift's own compiler
  emits a warning for `@available(*, deprecated)` usage. Treat that warning
  like any other — fix it, don't suppress it (see `shared_conventions.md`).

## Common pitfalls specific to this codebase

- Kotlin's `List<T>`/generic collections crossing into Swift via SKIE:
  verify the inferred Swift type matches what you expect (it usually does
  with SKIE, but confirm rather than assume — see the History feature's
  `HistoryViewModel.swift` for a worked example).
- A new Koin-resolved dependency needed from Swift requires a new getter on
  `KoinHelper` in `shared` — `get<T>()` cannot be called directly from
  Swift (inline reified functions don't export).
- If Xcode reports a stale/missing symbol from `TrailMetricsShared` right
  after a Kotlin-side change, check whether the Run Script phase actually
  ran (Report Navigator → latest build → "Build KMP Shared Framework") before
  assuming something is broken.
