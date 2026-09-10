# Android developer guide

Read `docs/coding-standards/shared_conventions.md` first — this document
only covers rules specific to the Android/Kotlin/Compose side.

## Architecture

- MVVM: `ViewModel` (androidx.lifecycle) exposes a single `StateFlow<UiState>`
  plus a `Flow<UiEvent>` for one-off events (navigation, snackbars). See any
  existing `RouteViewModel`/`TrackingViewModel`/`HistoryViewModel` for the
  pattern.
- Screens are stateless Composables that take a `UiState` and callbacks —
  no `ViewModel` reference inside a reusable Composable below the screen
  level.
- Use cases live in `domain`; a `ViewModel` calls a use case or a repository
  directly, never the other way around.
- New features get their own Gradle module under `androidApp/feature-<name>`,
  mirroring the existing `feature-route`/`feature-tracking`/`feature-history`
  structure (screen, ViewModel, `di/` Koin module).

## Dependency injection (Koin)

- One `val xModule = module { ... }` per feature/concern, in a `di/`
  subpackage.
- Register new feature modules in `androidApp/app/TrailMetricsApplication.kt`'s
  `initKoin { modules(...) }` call — `shared`'s `initKoin()` only knows about
  cross-platform modules, not Compose-UI-specific ones.
- Prefer constructor injection resolved via `get()`; avoid field injection
  or `KoinComponent` in application code (it's acceptable inside `shared`'s
  `KoinHelper` bridge for iOS interop only).

## Compose

- Stateless, hoisted state: a Composable takes state as parameters and
  reports changes via lambdas. Don't read a `ViewModel` inside a nested
  Composable — pass data down.
- `remember`/`rememberSaveable` for local UI state only (e.g. a text field
  draft); anything that survives process death or needs to be shared with
  business logic belongs in the `ViewModel`.
- Shared Composables (used by 2+ feature modules) go in
  `androidApp/core-ui`, not duplicated per feature.
- Preview functions (`@Preview`) are encouraged for new screens but are not
  a substitute for running the app.

## Testing

- `commonTest`/`test` uses JUnit4 + MockK + Google Truth for
  Android-specific tests; `domain`'s pure-Kotlin tests use `kotlin.test` +
  hand-written fakes (no MockK there — see `domain/README.md`).
- `UnconfinedTestDispatcher` for repository/coroutine tests unless the test
  specifically needs to control dispatch ordering.
- Robolectric is reserved for tests that need real Android framework
  simulation (`androidHostTest` in KMP modules, `test` in plain Android
  modules) — don't reach for it if a plain unit test would do.

## Enforcement (Detekt)

Config: `config/detekt.yml`, run via `./gradlew detekt` (also in CI).
Beyond the defaults already configured (`TooManyFunctions`, `LongMethod`,
`CyclomaticComplexMethod`, `LongParameterList`, `FunctionNaming`), the
following are turned on project-wide:

```yaml
style:
  ForbiddenMethodCall:
    active: true
    methods:
      - reason: 'Use a proper logger (or Koin-injected Logger) instead of println/print.'
        value: 'kotlin.io.println'
      - reason: 'Use a proper logger instead of print.'
        value: 'kotlin.io.print'
  ForbiddenImport:
    active: true
    imports:
      - value: 'kotlinx.coroutines.GlobalScope'
        reason: 'GlobalScope leaks coroutines outside any lifecycle. Inject or use viewModelScope/a scoped CoroutineScope instead.'
```

Every Kotlin module also sets `allWarningsAsErrors = true` in its
`compilerOptions` block, which turns Kotlin's own deprecation warnings into
build failures — this is what actually enforces "no deprecated APIs" (see
`shared_conventions.md`), not a Detekt rule.

Non-null assertion (`!!`) is not banned by tooling (Detekt's built-in
non-null-assertion rule has a high false-positive rate in Compose code),
but is discouraged in review — prefer `checkNotNull()` with a message, or
restructure to avoid the nullable type reaching that point.

## Common pitfalls specific to this codebase

- `AppRoute` lives in `core`'s `commonMain` — don't recreate a local route
  sealed class in a feature module.
- `RouteUiError` is the shared classification; the Android-only
  `stringRes` mapping lives in `androidApp/core-ui`'s
  `RouteUiErrorAndroid.kt`. Add new cases to both.
- After changing anything in `domain`, `data`, `core`, or `shared`, the app
  module and any KMP-dependent module needs a Gradle sync/rebuild — this is
  automatic for a normal Android Studio run, but be aware if you see stale
  behavior after a shared-module change.
