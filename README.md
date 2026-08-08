# TrailMetrics

![CI](https://github.com/ali-roozbahani/TrailMetrics/actions/workflows/ci.yml/badge.svg)

A modern Android app for tracking outdoor activities (running, cycling, walking) in real time — built with Kotlin, Jetpack Compose, and Clean Architecture as a portfolio project.

<div align="center">
  <img width="280" alt="TrailMetrics demo" src="https://github.com/user-attachments/assets/732abec0-d954-47f5-ac7a-3f45f165238c" />
</div>


---

## Overview

TrailMetrics lets a user plan a route by tapping waypoints on a map, start a live GPS-tracked activity session (running, cycling, or walking), and see real-time metrics — distance, elapsed time, speed, and calories burned — while the route is followed. On finish, the session is saved with a map snapshot and viewable later in an activity history, with a detail view comparing the planned route against the actual GPS path.

The project doubles as a hands-on space to practice and demonstrate production-grade Android patterns: strict Clean Architecture with a framework-free domain layer, a Foreground Service–backed tracking pipeline, structured concurrency with Kotlin Flow, Room persistence, and a modular Gradle setup with CI/static analysis.

**Core features so far:**
- Interactive route planning on Google Maps with waypoint tapping and closed-route generation (Google Directions API)
- Live GPS tracking with a Foreground Service and persistent notification (Android background-location compliant)
- Start / Pause / Resume / Stop session state machine
- Real-time distance, elapsed time, speed (GPS-reported with a windowed fallback), and MET-based calorie estimation
- Per-user profile (weight) and activity-type selection feeding into the calorie calculation
- Robust route-progress tracking on closed-loop routes (windowed nearest-point search)
- Activity history persisted with Room: list view with map-snapshot thumbnails, detail view with an interactive planned-vs-actual route map
- Bottom navigation between Route planning and History tabs, with full-screen tracking/detail flows outside the tab bar

---

## Architecture

TrailMetrics follows **Clean Architecture** with strict dependency inversion: the `domain` module has **zero Android dependencies** and is pure, testable Kotlin. This module structure is deliberately "light" modularization — enough to signal separation of concerns without turning module management into overhead for a solo project.

```
app/                 → DI graph assembly (Koin), Navigation host, bottom nav, wiring only
core/                → shared design system (theme, reusable Compose components, map UI)
domain/              → models, use cases, calculators — pure Kotlin, no Android dependency
data/                → repository implementations, Room persistence, location services, tracking service
feature-route/       → route planning screen (map, waypoints, activity selection)
feature-tracking/    → live tracking screen (start/pause/resume/stop, metrics, map snapshot capture)
feature-history/     → activity history list and detail screens
```

### Key modules and files

**Domain layer** (pure Kotlin, fully unit tested):
- [`TrackingSessionManager`](domain/src/main/kotlin/dev/roozbahani/trailmetrics/domain/tracking/TrackingSessionManager.kt) — orchestrates the tracking session: dispatches events, observes location updates, and manages transient GPS errors on a separate `SharedFlow` so they never contaminate the main state.
- [`UpdateTrackingStateUseCase`](domain/src/main/kotlin/dev/roozbahani/trailmetrics/domain/usecase/UpdateTrackingStateUseCase.kt) — a pure state-machine reducer (`TrackingState` + `TrackingEvent` → `TrackingState`), fully unit tested in isolation from Android.
- [`SpeedCalculator`](domain/src/main/kotlin/dev/roozbahani/trailmetrics/domain/util/SpeedCalculator.kt) — prefers the GPS chip's own speed estimate when accuracy is reliable, and falls back to a windowed distance/time calculation otherwise.
- [`CalorieCalculator`](domain/src/main/kotlin/dev/roozbahani/trailmetrics/domain/util/CalorieCalculator.kt) — MET-based calorie estimation (Compendium of Physical Activities), split into a per-activity-type function to keep cyclomatic complexity low.
- [`RouteProgress`](domain/src/main/kotlin/dev/roozbahani/trailmetrics/domain/model/RouteProgress.kt) — windowed nearest-point search that tracks progress along a planned route without jumping backward on closed loops.
- [`SaveActivityUseCase`](domain/src/main/kotlin/dev/roozbahani/trailmetrics/domain/usecase/SaveActivityUseCase.kt) — builds an `ActivityRecord` from the final tracking metrics, recomputing calories against the definitive elapsed time rather than trusting the last UI-observed value.
- [`Haversine`](domain/src/main/kotlin/dev/roozbahani/trailmetrics/domain/util/Haversine.kt) — great-circle distance calculation between coordinates.

**Data layer:**
- [`LocationRepositoryImpl`](data/src/main/kotlin/dev/roozbahani/trailmetrics/data/location/LocationRepositoryImpl.kt) — wraps `FusedLocationProviderClient` in a `callbackFlow`, properly handling `awaitClose` and `CancellationException` propagation.
- [`TrackingService`](data/src/main/kotlin/dev/roozbahani/trailmetrics/data/tracking/TrackingService.kt) — Foreground Service with a live-updating notification and an explicit `cancel()` on teardown to avoid stale notifications.
- [`UserProfileRepositoryImpl`](data/src/main/kotlin/dev/roozbahani/trailmetrics/data/user/UserProfileRepositoryImpl.kt) — SharedPreferences-backed persistence with `kotlinx.serialization`, resilient to corrupted data via `runCatching`.
- [`ActivityHistoryRepositoryImpl`](data/src/main/kotlin/dev/roozbahani/trailmetrics/data/local/repository/ActivityHistoryRepositoryImpl.kt) — Room-backed persistence for completed activities, exposing the saved list as a `Flow` that the history screen observes directly.
- [`TrailMetricsDatabase`](data/src/main/kotlin/dev/roozbahani/trailmetrics/data/local/database/TrailMetricsDatabase.kt) — single-entity Room database with `Converters` for `List<Coordinates>` (JSON-serialized) and `ActivityType`; schema export enabled for future migrations.

**Feature layer:**
- [`RouteScreen`](feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/RouteScreen.kt) / [`RouteViewModel`](feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/RouteViewModel.kt) — route planning UI and state.
- [`TrackingScreen`](feature-tracking/src/main/kotlin/dev/roozbahani/trailmetrics/feature/tracking/TrackingScreen.kt) / [`TrackingViewModel`](feature-tracking/src/main/kotlin/dev/roozbahani/trailmetrics/feature/tracking/TrackingViewModel.kt) — live tracking UI, combining session state with the user's profile to derive calories in real time, and capturing a `GoogleMap.snapshot()` on finish.
- [`HistoryScreen`](feature-history/src/main/kotlin/dev/roozbahani/trailmetrics/feature/history/HistoryScreen.kt) / [`HistoryViewModel`](feature-history/src/main/kotlin/dev/roozbahani/trailmetrics/feature/history/HistoryViewModel.kt) — activity list with map-snapshot thumbnails and per-activity metrics.
- [`DetailsScreen`](feature-history/src/main/kotlin/dev/roozbahani/trailmetrics/feature/history/DetailsScreen.kt) / [`DetailsViewModel`](feature-history/src/main/kotlin/dev/roozbahani/trailmetrics/feature/history/DetailsViewModel.kt) — single-activity detail view with an interactive map overlaying the planned route and the actual GPS path.

### Notable engineering decisions

- **State vs. event separation** — `StateFlow` is used for persistent UI state; one-shot navigation/permission/error events go through a `Channel`, so a stale event can never accidentally replay on recomposition or configuration change.
- **Domain purity via interfaces** — `TrackingSessionManager` depends only on `Clock`, `Logger`, `TrackingServiceLauncher`, and `LocationRepository` — all interfaces defined in `domain`, implemented in `data`. This keeps the orchestration logic testable without mocking Android framework classes.
- **Windowed route-progress search** — a naive "nearest point on route" search jumps backward on closed-loop routes when the path crosses near itself. Solved with a `searchWindow` parameter that limits the search to a bounded range ahead of the last known position — [see the test that documents both the bug and the fix](domain/src/test/kotlin/dev/roozbahani/trailmetrics/domain/model/RouteProgressTest.kt).
- **GPS speed with a safety net** — raw `Location.speed` is trusted only when reported accuracy is within an acceptable threshold; otherwise `SpeedCalculator` falls back to a small windowed distance/time average, filtering out GPS noise from single bad fixes.
- **Stop vs. Finish are distinct events** — leaving the tracking screen early (`Stop`) never persists an activity; only an explicit `Finish` click — reachable solely once the planned route is completed — triggers `SaveActivityUseCase`. Conflating the two would have silently persisted abandoned sessions.
- **Per-screen `Scaffold` for bottom navigation** — rather than a single global `Scaffold` wrapping the entire `NavHost` (which breaks edge-to-edge map rendering and forces manual `contentPadding` bookkeeping on every screen), each top-level destination owns its own `Scaffold` and accepts an optional `bottomBar` slot. This matches the pattern used in Google's official Compose samples and keeps padding correctness guaranteed by `Scaffold` itself rather than hand-computed.
- **Map snapshots are scaled, not just compressed** — `GoogleMap.snapshot()` returns a full-resolution `Bitmap`; since PNG is lossless, the only effective lever for file size is downscaling (not compression quality). Snapshots are capped at 600px wide before being written to disk, keeping the history list smooth while preserving sharp route-line edges.
- **Testing strategy** — pure domain logic (state machine, calculators, distance/progress math, `SaveActivityUseCase`) is tested with JUnit4 + Google Truth + MockK; Room- and SharedPreferences-backed persistence is tested with Robolectric against a real (simulated) `Context` and an in-memory database rather than hand-mocked.

---

## Tech Stack

| Category | Choice |
|---|---|
| Language | Kotlin |
| UI | Jetpack Compose, Material 3 |
| Architecture | Clean Architecture (domain / data / feature separation) |
| DI | Koin |
| Networking | Ktor (chosen over Retrofit for potential future Kotlin Multiplatform / iOS reuse) |
| Serialization | kotlinx.serialization |
| Maps & Location | Google Maps SDK, Google Directions API, FusedLocationProviderClient |
| Persistence | Room (activity history, with `TypeConverters` and schema export); SharedPreferences (user profile) |
| Image loading | Coil |
| Concurrency | Kotlin Coroutines & Flow |
| Testing | JUnit4, Google Truth, MockK, Robolectric |
| Static analysis | Android Lint, Detekt (custom ruleset in `config/detekt/detekt.yml`) |
| CI/CD | GitHub Actions (lint → detekt → test → assembleDebug on every PR and push to `main`) |
| Build | Gradle Version Catalog (`libs.versions.toml`) |

---

## Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/ali-roozbahani/TrailMetrics.git
   ```
2. Create a `local.properties` file in the project root (this file is git-ignored) with:
   ```properties
   MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY
   DIRECTIONS_API_KEY=YOUR_GOOGLE_DIRECTIONS_API_KEY
   ANDROID_CERT_SHA1=YOUR_DEBUG_SHA1_FINGERPRINT_NO_COLONS
   ```
   > Note: `ANDROID_CERT_SHA1` must be provided **without colons** (e.g. `AABBCC...`, not `AA:BB:CC...`) — the Directions API otherwise returns `REQUEST_DENIED`.
3. Open the project in Android Studio (Android Studio Quail 2 | 2026.1.2 Patch 1) and let Gradle sync.
4. Run on a device or emulator with Google Play services (min SDK 26).

---

## Testing

The `domain` module is covered by unit tests for the tracking state machine, distance/progress calculations, the speed/calorie calculators, and `SaveActivityUseCase` — all runnable without an emulator. Room- and SharedPreferences-backed repositories are tested with Robolectric, using an in-memory database for Room to exercise real query and type-conversion behavior rather than mocks.

```bash
./gradlew :domain:test
./gradlew :data:test
```

Static analysis (Android Lint + Detekt) runs alongside tests in CI on every pull request:

```bash
./gradlew lint
./gradlew detekt
```

---

## Roadmap

- [x] **Phase 0** — Project setup, module structure, CI skeleton
- [x] **Phase 1** — Map & route planning (waypoints, closed-route generation, distance calculation)
- [x] **Phase 2** — Live tracking (Foreground Service, state machine, route-progress detection)
- [x] **Phase 3** — Metrics (speed, calorie estimation, activity type, user profile)
- [x] **Phase 4** — Persistence & history (Room, map snapshots, activity list/detail screens, bottom navigation)
- [ ] **Phase 5** — Stretch goals (battery-aware location updates, Doze-mode resilience, Compose UI tests)

---

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.
