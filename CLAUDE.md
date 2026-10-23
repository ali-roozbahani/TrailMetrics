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
- `shared-uitest`  test-only variant of the framework: the iOS UI-test seam and the Swift test support; no production code depends on it
- `androidApp/{app,feature-*,core-ui}`  Compose UI, Android-only Koin modules
- `iosApp/{TrailMetrics.xcodeproj,Packages/*}`  SwiftUI, one SPM package per feature

Full module graph and rationale: `docs/architecture/OVERVIEW.md`.

## Skills (load the matching one before working)

Load the skill as the first tool call of a task, alone, before any other command (no
exploration in the same turn; for a task that ends in a PR, load `tm-pr-workflow` and
`tm-agent-loop` together there), and do `tm-pr-workflow`'s "Before starting" steps before the first
edit.

- `tm-kmp-shared`       anything in domain / data / core / shared, or a change that crosses platforms
- `tm-android`          anything under androidApp/
- `tm-ios`              anything under iosApp/
- `tm-testing`          writing or changing tests on any platform
- `tm-robustness`       any Kotlin or Swift change, with the area skill (crashes, ANR, exceptions, threads, leaks)
- `tm-pr-workflow`      every task that ends in a commit, push or PR (branching, gate, PR description)
- `epic-orchestration`  a change big enough to split into parallel subtasks across layers/platforms
- `tm-agent-loop`       every task that ends in a PR, named or picked from the board ("take the next
                        task"); with `tm-pr-workflow`

Open epics, tasks and drift live in `BOARD.md`; how to add and remove records: `tm-pr-workflow` → "Board".

## Presentation layer: MVI

All four Android ViewModels (`RouteViewModel`, `TrackingViewModel`, `HistoryViewModel`,
`DetailsViewModel`) have been migrated from the old public-methods style (`onStartClicked()`,
`onPauseClicked()`, ...) to MVI (`onAction(Action)`, single `Action`/`Event` sealed types).
`tm-android`'s MVI section is the target shape for every new screen and ViewModel; it also
lists the remaining known deviations in the migrated code, which are not to be copied.

## Testing stack (fixed, do not introduce alternatives)

`kotlin.test` for `domain` and any other commonTest/KMP code, with hand-written fakes;
HTTP-level repository tests in `data` commonTest use Ktor `MockEngine` (`ktor-client-mock`).
Android tests: JUnit4 + `kotlin.test` assertions + `kotlinx-coroutines-test` + hand-written
fakes; Robolectric (catalog entry) runs the tests that need the Android framework; each module's
`build.gradle.kts` is the source of truth for which modules use it.
MockK and Turbine are not in the catalog. No JUnit5, no AssertK, no Truth. Details: `tm-testing`.

## Hard rules (always apply)

- Never commit to or push to `main`. Work on a branch: `feature/`, `bugfix/` or `chore/` prefix.
- Never call a deprecated API. Never add a third-party dependency unless the task names it.
- Never cross a module boundary listed in `tm-kmp-shared`; stop and report instead.
- Before any push, `scripts/pre-push-check.sh` must pass locally. Unless
  `scripts/classify-changes.sh` decides `light` (non-source changes only), it runs Gradle
  `detekt`, `lint`, `allTests test` and `assembleDebug` (plus SwiftLint and the iOS build when
  iOS code or shared code changed), a non-blocking merged Kover coverage report, and an enforced
  `koverVerify` (per-module minimum line coverage). CI's heavy steps follow the same decision.
  `./gradlew test` alone runs zero KMP tests.
- Do not change docs/architecture, CI config, lint config or this file as a side effect
  of an unrelated task. Fixing a skill or CLAUDE.md line that describes the exact code the
  task changed, or the wiring (CI, gate, CODEOWNERS) of a file it adds or changes, is part
  of the task, not a side effect (see `tm-pr-workflow`).
- If docs or conventions are ambiguous for the task, state the assumption you made.
