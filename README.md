# TrailMetrics

![CI](https://github.com/ali-roozbahani/TrailMetrics/actions/workflows/ci.yml/badge.svg)

A cross-platform (Android + iOS) app for tracking outdoor activities (running, cycling, walking) in real time — built with Kotlin Multiplatform, Jetpack Compose, and SwiftUI as a portfolio project.

<div align="center">
  <img width="280" alt="TrailMetrics demo" src="https://github.com/user-attachments/assets/732abec0-d954-47f5-ac7a-3f45f165238c" />
</div>

---

## Overview

TrailMetrics lets a user plan a route by tapping waypoints on a map, start a live GPS-tracked activity session (running, cycling, or walking), and see real-time metrics — distance, elapsed time, speed, and calories burned — while the route is followed. On finish, the session is saved with a map snapshot and viewable later in an activity history, with a detail view comparing the planned route against the actual GPS path.

The project started as an Android-only app and is being migrated to Kotlin Multiplatform, sharing business logic, persistence, networking, and navigation identity between a Jetpack Compose Android app and a native SwiftUI iOS app — while keeping the UI layer 100% native per platform (see [`docs/architecture/ADR-001-no-compose-multiplatform.md`](docs/architecture/ADR-001-no-compose-multiplatform.md) for why).

It doubles as a hands-on space to practice and demonstrate production-grade patterns on both platforms: strict Clean Architecture with a framework-free domain layer, a Foreground Service–backed tracking pipeline, structured concurrency with Kotlin Flow, Room persistence shared across platforms, Koin dependency injection with a cross-platform composition root, and a fully modular, statically-analyzed, CI-enforced codebase.

**Core features so far (Android — complete; iOS — in progress, feature by feature):**
- Interactive route planning on a map with waypoint tapping and closed-route generation (Google Directions API)
- Live GPS tracking with a background-location pipeline and Start / Pause / Resume / Stop session state machine
- Real-time distance, elapsed time, speed, and MET-based calorie estimation
- Per-user profile (weight) and activity-type selection feeding into the calorie calculation
- Robust route-progress tracking on closed-loop routes (windowed nearest-point search)
- Activity history persisted with Room: list view with map-snapshot thumbnails, detail view with an interactive planned-vs-actual route map
- Cross-platform navigation identity (`AppRoute`) shared between Android's Navigation Compose and iOS's `NavigationStack`

---

## Architecture

TrailMetrics follows **Clean Architecture** with strict dependency inversion. The `domain` module has **zero Android or iOS dependencies** and is pure, testable Kotlin. Business logic, persistence, and navigation identity live in Kotlin Multiplatform modules shared by both platforms; UI is implemented natively per platform.

**The full architecture — module graph, platform strategy, dependency injection, navigation, and the reasoning behind each decision — is documented in [`docs/architecture/OVERVIEW.md`](docs/architecture/OVERVIEW.md).** That document, its linked ADRs (Architecture Decision Records), and each module's own `README.md` are the source of truth; what follows here is a summary.

```
domain/               → pure Kotlin: models, use cases, repository interfaces. Zero platform dependency
data/                 → KMP: repository implementations, Room, Ktor, platform-specific location/tracking via expect/actual
core/                 → KMP, commonMain only: AppRoute (navigation identity), RouteUiError (error classification)
shared/               → KMP umbrella module: Koin composition root, XCFramework export for iOS

androidApp/
  app/                 → Android composition root: NavHost, Application class, Koin wiring
  feature-route/       → route planning screen (map, waypoints, activity selection)
  feature-tracking/    → live tracking screen (start/pause/resume/stop, metrics, map snapshot capture)
  feature-history/     → activity history list and detail screens
  core-ui/             → Compose design system + Google Maps Compose components (Android-only, see ADR-003)

iosApp/
  TrailMetrics.xcodeproj → iOS composition root: SwiftUI App struct, Koin init
  Packages/SharedKit      → thin Swift Package wrapping the shared XCFramework
  Packages/<Feature>      → one local Swift Package per feature (History done; Route, Tracking in progress)
```

### Notable engineering decisions

- **State vs. event separation** — `StateFlow`/`@Published` for persistent UI state; one-shot navigation/permission/error events go through a `Channel` (Android) or are handled explicitly in the ViewModel (iOS), so a stale event can never accidentally replay.
- **Domain purity via interfaces** — `TrackingSessionManager` depends only on `Clock`, `Logger`, `TrackingServiceLauncher`, and `LocationRepository` — all interfaces defined in `domain`, implemented per-platform in `data`. This keeps orchestration logic testable without mocking any platform framework.
- **Windowed route-progress search** — a naive "nearest point on route" search jumps backward on closed-loop routes when the path crosses near itself. Solved with a `searchWindow` parameter bounding the search to a range ahead of the last known position.
- **Stop vs. Finish are distinct events** — leaving the tracking screen early (`Stop`) never persists an activity; only an explicit `Finish` click triggers `SaveActivityUseCase`. Conflating the two would have silently persisted abandoned sessions.
- **Shared navigation identity, native navigation mechanics** — `AppRoute` (a plain `@Serializable` sealed interface in `core`) is the single source of truth for what screens exist; each platform wires it into its own idiomatic navigation API (Navigation Compose's type-safe `composable<T>()` on Android, `NavigationStack`/`NavigationPath` on iOS via SKIE's Swift enum export) rather than sharing a navigation framework itself.
- **`core` (KMP) vs. `core-ui` (Android-only) are deliberately separate modules** — the Compose compiler Gradle plugin instruments every Kotlin compilation in a module it's applied to, including iOS targets, so Compose code cannot coexist with an iOS target in the same module. See [`ADR-003-core-ui-split.md`](docs/architecture/ADR-003-core-ui-split.md).
- **Testing strategy** — pure domain logic uses `kotlin.test` with hand-written fakes (Kotlin/Native has no reflection, so no MockK in shared modules); Android-only persistence tests use Robolectric where genuinely needed. See [`domain/README.md`](domain/README.md) and [`data/README.md`](data/README.md).

---

## AI-assisted development

This project is developed with an AI coding agent (Claude, via Claude Code) as a core part of the workflow, not an ad-hoc add-on — and it's set up deliberately to keep that assistance safe, reviewable, and drift-resistant:

- **`docs/architecture/`** — the module graph, platform strategy, and every non-obvious architectural decision, written as ADRs with their reasoning, not just their conclusion.
- **`docs/coding-standards/`** — naming, dependency, and API-usage rules for each platform, most of which are **enforced by tooling** (Detekt for Kotlin, SwiftLint for Swift — both run in CI), not left to convention alone.
- **`docs/workflow/coding_agent_workflow.md`** — the standard process and prompt template for delegating a feature or fix to a coding agent: what context it must read first, what it's never allowed to do unprompted (commit, merge, add a dependency, cross a module boundary), and how its output gets reviewed before merging.
- Every module has its own `README.md` describing its role and boundaries, so an agent (or a new contributor) can answer "does this belong here?" without guessing.

The goal is that anyone reading this repository — human or automated — can tell what's allowed to change, what isn't, and why, before writing a single line of code.

---

## Tech Stack

| Category | Choice |
|---|---|
| Language | Kotlin (shared + Android), Swift (iOS) |
| Cross-platform | Kotlin Multiplatform, Koin (shared DI), SKIE (Swift interop for Flow/coroutines) |
| UI | Jetpack Compose + Material 3 (Android), SwiftUI (iOS) |
| Architecture | Clean Architecture (domain / data / core / shared / feature separation) |
| Networking | Ktor (OkHttp engine on Android, Darwin on iOS) |
| Serialization | kotlinx.serialization |
| Maps & Location | Google Maps SDK (Android Compose + iOS via native Swift), Google Directions API, FusedLocationProviderClient / CoreLocation |
| Persistence | Room 3.x (KMP, shared between Android and iOS), SharedPreferences / NSUserDefaults for user profile |
| Image loading | Coil (Android) |
| Concurrency | Kotlin Coroutines & Flow |
| Testing | `kotlin.test` + hand-written fakes (shared), JUnit4 + Google Truth + MockK + Robolectric (Android-only) |
| Static analysis | Detekt (`config/detekt/detekt.yml`), SwiftLint (`iosApp/.swiftlint.yml`), Android Lint |
| CI/CD | GitHub Actions — separate Android (`ubuntu-latest`) and iOS (`macos-latest`) jobs on every PR and push to `main` |
| Build | Gradle Version Catalog (`libs.versions.toml`), Swift Package Manager (iOS local packages) |

---

## Setup

### Android
1. Clone the repository:
   ```bash
   git clone https://github.com/ali-roozbahani/TrailMetrics.git
   ```
2. Create a `local.properties` file in the project root (git-ignored) with:
   ```properties
   MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY
   DIRECTIONS_API_KEY=YOUR_GOOGLE_DIRECTIONS_API_KEY
   ANDROID_CERT_SHA1=YOUR_DEBUG_SHA1_FINGERPRINT_NO_COLONS
   ```
   > Note: `ANDROID_CERT_SHA1` must be provided **without colons** — the Directions API otherwise returns `REQUEST_DENIED`.
3. Open the project in Android Studio and let Gradle sync.
4. Run the `androidApp:app` configuration on a device or emulator with Google Play services (min SDK 26).

### iOS
1. Requires a Mac with Xcode installed.
2. Build the shared Kotlin framework once before first open:
   ```bash
   ./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework
   ```
3. Open `iosApp/TrailMetrics.xcodeproj` in Xcode. Its build phases rebuild the shared framework automatically (incrementally, only when `domain`/`data`/`shared` Kotlin source changes) — see `docs/architecture/OVERVIEW.md`.
4. Run on an iOS Simulator or device.

---

## Testing & static analysis

```bash
# Shared Kotlin logic (runs on JVM, Android host, and iOS Simulator targets)
./gradlew :domain:allTests
./gradlew :data:allTests

# Android static analysis
./gradlew lint
./gradlew detekt

# iOS static analysis
cd iosApp && swiftlint lint --strict
```

Both Android and iOS have their own CI job (`.github/workflows/ci.yml`) running lint/static-analysis, tests, and a full build on every pull request and push to `main`.

---

## Documentation

- [`docs/architecture/OVERVIEW.md`](docs/architecture/OVERVIEW.md) — module graph, platform strategy, DI, navigation
- [`docs/architecture/ADR-001-no-compose-multiplatform.md`](docs/architecture/ADR-001-no-compose-multiplatform.md), [`ADR-002-shared-umbrella-module.md`](docs/architecture/ADR-002-shared-umbrella-module.md), [`ADR-003-core-ui-split.md`](docs/architecture/ADR-003-core-ui-split.md)
- [`docs/coding-standards/shared_conventions.md`](docs/coding-standards/shared_conventions.md), [`android_developer_guide.md`](docs/coding-standards/android_developer_guide.md), [`ios_developer_guide.md`](docs/coding-standards/ios_developer_guide.md)
- [`docs/workflow/coding_agent_workflow.md`](docs/workflow/coding_agent_workflow.md)
- [`LEARNINGS.md`](LEARNINGS.md) — chronological log of concrete technical gotchas hit during development
- Per-module `README.md` in `domain/`, `data/`, `core/`, `shared/`, `androidApp/core-ui/`

---

## Roadmap

- [x] **Phase 0–4** — Android app complete: project setup, map & route planning, live tracking, metrics, persistence & history
- [x] **KMP migration, Phase A–B** — `domain` and `data` converted to Kotlin Multiplatform
- [x] **KMP migration, Phase C** — `shared` umbrella module, XCFramework export, SKIE, Koin cross-platform composition root
- [x] **KMP migration, Phase D** — iOS app skeleton, SPM modularization, first feature (History) ported end-to-end
- [x] **KMP migration, Phase E–H** — shared `AppRoute` navigation identity, `androidApp` restructuring, `core`/`core-ui` split
- [x] **KMP migration, Phase I** — enforced coding standards (Detekt + SwiftLint), architecture documentation, dual-platform CI
- [ ] iOS: Route feature
- [ ] iOS: Tracking feature
- [ ] iOS: cross-feature navigation, full app parity with Android
- [ ] Stretch goals (battery-aware location updates, Doze-mode resilience, Compose/SwiftUI UI tests)

---

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.
