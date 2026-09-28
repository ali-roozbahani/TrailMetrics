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

- `tm-kmp-shared`  anything in domain / data / core / shared, or a change that crosses platforms
- `tm-android`     anything under androidApp/
- `tm-testing`     writing or changing tests on any platform

## Presentation layer: migration in progress

ViewModels are being migrated from a plain public-methods style (`onStartClicked()`,
`onPauseClicked()`, ...) to MVI (`onAction(Action)`, single `Action`/`Event` sealed types).
`tm-android` documents the MVI **target** shape. Do not assume every existing ViewModel
already follows it — check the file before copying its pattern, and never use an
unmigrated ViewModel as a reference for a new one.

## Testing stack (fixed, do not introduce alternatives)

JUnit4 + MockK, for Android-framework tests (Robolectric, Compose UI). `kotlin.test` (no
JUnit5, no AssertK) for `domain` and any other commonTest/KMP code. No Truth — being
removed project-wide; if you see `com.google.truth.Truth` imports outside an
in-progress migration task, that's stale, flag it rather than adding more.

## Hard rules (always apply)

- Never commit to or push to `main`. Work on a branch: `feature/`, `bugfix/` or `chore/` prefix.
- Never call a deprecated API. Never add a third-party dependency unless the task names it.
- Never cross a module boundary listed in `tm-kmp-shared`; stop and report instead.
- Before any push, all of these must pass locally: `./gradlew detekt lint test assembleDebug`
  (plus SwiftLint and the iOS build when iOS code or shared code changed).
- Do not change docs/architecture, CI config, lint config or this file as a side effect
  of an unrelated task.
- If docs or conventions are ambiguous for the task, state the assumption you made.
