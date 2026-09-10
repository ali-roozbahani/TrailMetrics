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
- `shared` is the only module allowed to apply SKIE and to define
  `binaries.framework { ... }` — no other module exports anything to iOS
  directly.
- iOS's `SharedKit` Swift Package wraps `TrailMetricsShared.xcframework`
  once, so every iOS feature package depends on `SharedKit`, never the
  XCFramework directly (see `docs/architecture/OVERVIEW.md`).
