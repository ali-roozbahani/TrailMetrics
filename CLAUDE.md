# TrailMetrics

Cross-platform GPS activity tracker. Shared business logic in Kotlin Multiplatform,
native UI per platform (Jetpack Compose on Android, SwiftUI on iOS).
Compose Multiplatform is a deliberate non-goal (docs/architecture/ADR-001).

## Map

- `domain`  pure Kotlin: models, use cases, repository interfaces, session state machines
  (e.g. `TrackingSessionManager`)
- `data`    repository implementations, Room, Ktor, expect/actual platform services
- `core`    commonMain only: `AppRoute`, `RouteError`/`RouteUiError` (no UI framework)
- `shared`  umbrella: Koin composition root (`initKoin`), XCFramework export, `KoinHelper`
- `androidApp/{app,feature-*,core-ui}`  Compose UI, Android-only Koin modules
- `iosApp/{TrailMetrics.xcodeproj,Packages/*}`  SwiftUI, one SPM package per feature

Full module graph and rationale: `docs/architecture/OVERVIEW.md`.

## Skills (load the matching one before working)

- `tm-kmp-shared`       anything in domain / data / core / shared, or a change that crosses platforms
- `tm-android`          anything under androidApp/
- `tm-ios`              anything under iosApp/
- `tm-testing`          writing or changing tests on any platform
- `tm-pr-workflow`      every task that ends in a commit, push or PR (branching, gate, PR description)
- `epic-orchestration`  a change big enough to split into parallel subtasks across layers/platforms

## Presentation layer: MVI

All four Android ViewModels (`RouteViewModel`, `TrackingViewModel`, `HistoryViewModel`,
`DetailsViewModel`) have been migrated from the old public-methods style (`onStartClicked()`,
`onPauseClicked()`, ...) to MVI (`onAction(Action)`, single `Action`/`Event` sealed types).
`tm-android`'s MVI section is the target shape for every new screen and ViewModel; it also
lists the remaining known deviations in the migrated code, which are not to be copied.

## Testing stack (fixed, do not introduce alternatives)

JUnit4 + MockK, for Android-framework tests (Robolectric, Compose UI). `kotlin.test` (no
JUnit5, no AssertK) for `domain` and any other commonTest/KMP code. No Truth — being
removed project-wide; if you see `com.google.truth.Truth` imports outside an
in-progress migration task, that's stale, flag it rather than adding more.

## Hard rules (always apply)

- Never commit to or push to `main`. Work on a branch: `feature/`, `bugfix/` or `chore/` prefix.
- Never call a deprecated API. Never add a third-party dependency unless the task names it.
- Never cross a module boundary listed in `tm-kmp-shared`; stop and report instead.
- Before any push, `scripts/pre-push-check.sh` must pass locally. It runs Gradle `detekt`,
  `lint`, `allTests test` and `assembleDebug` (plus SwiftLint and the iOS build when iOS
  code or shared code changed), and a non-blocking merged Kover coverage report. `./gradlew test` alone runs zero KMP tests.
- Do not change docs/architecture, CI config, lint config or this file as a side effect
  of an unrelated task. Fixing a skill or CLAUDE.md line that describes the exact code the
  task changed is part of the task, not a side effect (see `tm-pr-workflow`).
- If docs or conventions are ambiguous for the task, state the assumption you made.
