# ADR-002: `shared` as a dedicated umbrella module

## Status
Accepted.

## Context
To consume Kotlin code from iOS, one or more KMP modules must be exported
as an XCFramework, and a Koin composition root must exist that both
platforms can call into. Two approaches were considered:
- **(a)** Export directly from the `data` module (which already depends on
  `domain`), adding `binaries.framework { ... }` and the Koin `initKoin()`
  entry point there.
- **(b)** Create a separate module (`shared`) whose only job is to
  aggregate `domain`/`data`/`core` and expose them as a single XCFramework
  plus a cross-platform Koin entry point.

## Decision
Use a dedicated `shared` umbrella module (option b).

## Reasoning
- This is the pattern used by JetBrains' own "Kotlin Multiplatform Shared
  Module" Android Studio template and documented in real-world KMP sample
  projects (an "umbrella module" aggregating multiple `core:*`-style
  modules behind one XCFramework).
- Official Koin documentation recommends exactly this shape for
  cross-platform composition roots: a shared `initKoin()` function in
  `commonMain` with `expect`/`actual` platform module lists, called from
  each platform's real entry point (Android `Application`, iOS `App`
  struct).
- Separation of concerns: `data`'s job is implementing repositories, not
  deciding how iOS consumes the app. Keeping the export/composition
  concern in its own module means `data` doesn't grow a second
  responsibility, and adding a new shareable module later (if one is ever
  needed) has an obvious place to be wired in.

## Consequences
- `shared` depends on `domain`, `data`, and `core` as `api(...)` (required
  for Kotlin/Native's `export()` to expose their symbols to Swift).
- `shared` is the only module that exports production API to iOS: no
  other module applies SKIE or defines `binaries.framework { ... }` for
  production. One exception, for UI tests only (see "Amendment"):
  `shared-uitest` builds a test-only variant of the same framework.
- iOS's `SharedKit` Swift Package wraps `TrailMetricsShared.xcframework`
  once, so every iOS feature package depends on `SharedKit`, never the
  XCFramework directly (see `docs/architecture/OVERVIEW.md`).

## Amendment (2026-10-14): a test-only variant of the framework

### Context
The iOS UI tests (`docs/epics/ios-ui-tests.md`) need in-memory Kotlin fakes
for location, directions, history storage and the user profile, entered
through a Koin override at launch. A second Kotlin framework next to
`TrailMetricsShared` could not share its types, and putting the fakes into
`shared` would ship test code in every build of the production framework,
Release included.

### Decision
`shared` stays the only module that exports production API to iOS;
`shared-uitest` builds only a test-only variant of the same framework,
linked by UI-test builds alone.

- `shared-uitest` depends on `shared` with `api(...)`, applies SKIE and
  defines one DEBUG-only static framework with the same `baseName`
  (`TrailMetricsShared`), exporting `shared`, `domain`, `data` and `core`
  like `shared` does, plus its own UI-test seam (package
  `dev.roozbahani.trailmetrics.uitest`). It is the same Swift module, with
  production's API plus the seam.
- `shared` does not change and never depends on `shared-uitest`; no
  production code does.
- `scripts/build-kmp-framework.sh` builds the variant only when asked for
  it (the `Debug-UITest` Xcode configuration, or `--variant uitest`),
  checks with `scripts/check-variant-api.sh` that its API is production's
  plus the seam's declarations, and
  copies it over the production framework's debug path
  (`shared/build/XCFrameworks/debug/TrailMetricsShared.xcframework`), so
  `SharedKit/Package.swift` does not change. Its stamp records which
  variant is in place, so the next normal build replaces the variant with
  the production framework again.
- Normal Debug and Release builds never link the variant. The
  `Debug-UITest` configuration, the UI-test scheme and the Swift call site
  that enters the seam come with later subtasks of the epic (S2, S3).

### Consequences
- Two modules apply SKIE and define a framework named `TrailMetricsShared`;
  only `shared`'s is production. A third one needs a new decision.
- The variant's API can drift from production's (`scripts/check-variant-api.sh`
  catches it; one known difference, a swap of two `cancel` labels in
  Kotlin library types, is normalised there and documented in the script).
