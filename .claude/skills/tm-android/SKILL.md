---
name: tm-android
description: Use when writing or changing Android code in TrailMetrics under androidApp/ — Compose screens, ViewModels, Koin wiring, feature modules, core-ui. Covers the MVI target shape for ViewModels, Compose conventions, Koin registration, Gradle module setup, Kotlin naming/deprecation/dead-code rules and Detekt. Not for domain/data/core/shared (see tm-kmp-shared) or for test code (see tm-testing).
---

# TrailMetrics Android

This skill is the source of truth for Android conventions (it replaced the retired
`android_developer_guide.md` and `shared_conventions.md`). It records both the rules and what
the current code under `androidApp/` actually does. Where they differ, the code wins for "what
exists", this skill's MVI section wins for "what new ViewModels should look like".

## Architecture

- One Gradle module per feature under `androidApp/feature-<name>` (`feature-route`,
  `feature-tracking`, `feature-history`), each holding its screen(s), ViewModel(s) and a
  `di/` Koin module. Package `dev.roozbahani.trailmetrics.feature.<name>`, same as the
  Gradle `namespace`.
- Feature modules depend only on `:domain`, `:core` and `:androidApp:core-ui` (plus
  `:androidApp:core-testing`, via `testImplementation` only). They never
  depend on each other, on `:data` or on `:shared`. Only `:androidApp:app` sees everything.
  Cross-feature navigation is wired in the app module (`TrailMetricsNavHost` in
  `MainActivity.kt`). Screens ask for navigation through callback parameters
  (`HistoryScreen(onActivityClicked = ...)`); they don't hold a `NavController`.
- A ViewModel calls a `domain` use case, a repository interface or a domain state machine
  (`TrackingSessionManager`) directly. Dependencies point that way only: nothing in
  `domain`/`data` knows about a ViewModel.
- `AppRoute` lives in `core`'s `commonMain` and is the single source of destinations. Never
  recreate a local route sealed class in a feature module.
- `RouteUiError` (in `core`) is the shared error classification. Its Android-only
  `stringRes` mapping lives in `androidApp/core-ui`'s `error/RouteUiErrorAndroid.kt`. A new
  `RouteUiError` case needs a branch there (plus the string in `core-ui`'s `strings.xml`) in
  the same change. The `when` is exhaustive, so the build fails if you forget.
- Composables used by 2+ feature modules go in `androidApp/core-ui` (`designsystem/theme`,
  `designsystem/component`, `map/`, `error/`), not duplicated per feature. A composable
  with a single consumer stays in its feature until a second feature needs it (see
  `core-ui/README.md`). Anything with no UI-framework dependency belongs in the KMP `core`
  module instead, so iOS can share it.

## Presentation layer — MVI (target shape)

Every screen has:
1. **State** — one data class with all UI state fields.
2. **Action** — sealed interface of user-triggered actions, entry point `onAction(Action)`.
3. **Event** — sealed interface of one-time side effects (navigation, snackbar), delivered
   via `Channel`, never a plain callback lambda.
4. **ViewModel** — `StateFlow<State>` + `onAction()`, no other public methods.

**Current code: all four Android ViewModels are migrated** (`RouteViewModel` in #50,
`HistoryViewModel`/`DetailsViewModel` in #53, `TrackingViewModel` in #54). Each exposes
`val state: StateFlow<<X>State>`, `val events: Flow<<X>Event>` backed by a `Channel`, and a
single public `onAction(<X>Action)`. Each screen file has a `<X>Root` that gets the
ViewModel via `koinViewModel()` and collects events, and a stateless `<X>Screen(state,
onAction, ...)`. Any of the four is a valid reference for a new screen, apart from the
NavHost-overload deviation noted under "Known deviations". (`TrackingViewModel`'s state is
`TrackingScreenState`, renamed to avoid the domain `TrackingState` clash below.)

The migrated ViewModels replaced an older pattern (public methods like `onStartClicked()`,
`onPauseClicked()`, and a callback parameter `onFinishClicked(path, onSaved: () -> Unit)`
in the pre-#54 `TrackingViewModel.kt`). If you ever migrate a ViewModel from that style:
- `onFinishClicked(snapshotFilePath, onSaved: () -> Unit)` becomes
  `onAction(Action.Finish(snapshotFilePath))`, with success signaled by an `Event`
  (e.g. `Event.Saved`) that the Root composable observes — not a callback parameter.
- `startedAtEpochMillis` as a bare `var` on the ViewModel should move into `State` or
  stay as private implementation state only if it never needs to survive process death;
  don't carry it forward as a public/mutable field.
- Computed properties on the UI state (`canStart`, `canPause`, `currentMetrics`, ...)
  are fine to keep as `State` getters — that part of the current design already matches
  the target shape and should not be rewritten.
- Do NOT copy from an unmigrated ViewModel as your reference pattern. Check whether the
  file you're using as a model has itself been migrated first.

```kotlin
data class TrackingState(  // careful: this name collides with the existing domain
    val trackingState: DomainTrackingState = DomainTrackingState.Idle,  // rename as needed
    val calories: Double? = null
)

sealed interface TrackingAction {
    data class Start(val startCoordinates: Coordinates) : TrackingAction
    data object Pause : TrackingAction
    data object Resume : TrackingAction
    data object Stop : TrackingAction
    data class Finish(val snapshotFilePath: String?) : TrackingAction
}

sealed interface TrackingEvent {
    data object RequestLocationPermission : TrackingEvent
    data class ShowError(val error: RouteUiError) : TrackingEvent
    data object Saved : TrackingEvent
}
```

Naming: `<Screen>State`, `<Screen>Action`, `<Screen>Event`, `<Screen>Root` (holds
ViewModel via `koinViewModel()`, observes events), `<Screen>Screen` (pure `state` +
`onAction`, previewable, no ViewModel reference). Root and Screen live in the same file.

## Koin

Match `TrailMetricsApplication.kt`'s existing style exactly:
- One `val <x>Module = module { ... }` per feature (`trackingUiModule`, `routeModule`,
  `historyUiModule`), in that feature's `di/` subpackage
  (`feature/tracking/di/TrackingUiModule.kt`), registered in `initKoin { modules(...) }`
  inside `TrailMetricsApplication.onCreate()`
  (`androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/`). `shared`'s `initKoin()`
  only registers cross-platform modules; Compose-UI modules must be passed in here.
- Prefer `viewModelOf(::MyViewModel)` / `singleOf(::Impl)` constructor-reference form.
  Only fall back to the lambda form (`viewModel { ... }`) when you need a factory
  method, a qualifier, runtime parameters (`params.get()`), or post-construction setup.
  Today every module uses the lambda form, including `HistoryViewModel` and
  `RouteViewModel`, which have no parameters; don't take that as the pattern for new code.
- Constructor injection only, resolved with `get()`. No field injection (`by inject()`) and
  no `KoinComponent` in application code. `KoinComponent` is acceptable only inside
  `shared`'s `KoinHelper` bridge for iOS. Existing exception: `MainActivity` field-injects
  `TrackingSessionManager` with `by inject()`. Don't copy it.
- Cross-platform bindings (anything iOS also needs via `KoinHelper`) go in `shared`/
  `data`, not here — see `tm-kmp-shared`.
- Always inject ViewModels with `koinViewModel()` in the Root composable. Never pass a
  ViewModel down the composable tree.

## Compose

- The UI is dumb: composables render `state` and forward `Action`s via `onAction`.
  Zero business logic, zero data transformation in composables. Logic like route
  progress/completion belongs in the ViewModel (or `domain`, if iOS needs it too):
  `TrackingViewModel` owns it through `RouteCompletionTracker` (moved out of a
  `TrackingScreen` `LaunchedEffect` in #54).
- Stateless and hoisted: a composable takes state as parameters and reports changes through
  lambdas. Below the Root, no composable reads a ViewModel; pass data down.
- State lives in the ViewModel's `StateFlow`, collected with
  `collectAsStateWithLifecycle()`. `remember`/`rememberSaveable` are only for view-local UI
  state that business logic never needs: Compose-owned holders (`LazyListState`,
  `SnackbarHostState`, `rememberCameraPositionState()`), dialog/sheet visibility
  (`showDeleteConfirmation`), or a text-field draft before it's submitted (`weightInput`).
  Anything that must survive process death or that business logic reads belongs in the
  ViewModel.
- Collect events in a `LaunchedEffect` in the Root, with an exhaustive `when`.
- Animate below the recomposition layer: `graphicsLayer`, offset lambdas, or
  `animateFloatAsState` feeding into `graphicsLayer` — not `Modifier.alpha(animatedValue)`
  directly.
- Every new Screen composable gets at least one `@Preview` with realistic sample state,
  wrapped in `TrailMetricsTheme`. A preview doesn't replace running the app. Each of the
  four screens has one (`RouteScreenPreview`, `TrackingScreenPreview`,
  `HistoryScreenPreview`, `DetailsScreenPreview`; `RouteScreen.kt` also has
  `ActivityTypeSelectorPreview`). Follow the four screen previews' form: a `private`
  function with `@Suppress("UnusedPrivateMember")`, because Detekt counts it as unused,
  and a one-line comment saying so.
- Meaningful `contentDescription` (via string resources, `cd_*` keys) on
  interactive/informational elements; `null` for purely decorative ones.
- Colors and typography come from `core-ui`'s `designsystem/theme`; no ad-hoc color
  literals in features.

## Module / Gradle conventions

New feature modules follow the existing `androidApp/feature-tracking`-style layout:
`com.android.library` + `org.jetbrains.kotlin.plugin.compose` plugins (Kotlin comes from
AGP 9's built-in support; there is no `kotlin-android` plugin), `compileSdk` via
`release(37) { minorApiLevel = 1 }`, `minSdk 26`, Java 11 source/target compatibility,
`buildFeatures { compose = true }`, dependencies on `:domain`, `:core`,
`:androidApp:core-ui`, plus the Compose BOM and Koin BOM (see an existing module's
`build.gradle.kts` for the exact block — copy its structure, don't hand-roll a new one).
Register it in `settings.gradle.kts` and add it to `:androidApp:app`'s dependencies.
All versions come from `libs.versions.toml` — never hardcode a version in a module's
`build.gradle.kts`. Never add a third-party dependency unless the task names it.

After changing anything in `domain`, `data`, `core` or `shared`, dependent Android modules
need a Gradle sync/rebuild. A normal Android Studio run does this automatically. If you see
stale behavior right after a shared-module change, suspect this first.

## Naming (Kotlin)

- Gradle modules: lowercase, hyphenated (`feature-history`). Packages: lowercase dot
  segments, no underscores (`dev.roozbahani.trailmetrics.feature.history`, never
  `featurehistory` or `feature_history`). Detekt's `PackageNaming` only rejects underscores
  and uppercase-leading segments, so the rest is review-enforced.
- Classes/interfaces/objects `PascalCase`; interfaces carry no `I` prefix
  (`ActivityHistoryRepository`, not `IActivityHistoryRepository`). Functions/properties
  `camelCase`. `@Composable` functions are `PascalCase` (Detekt's `FunctionNaming` ignores
  `@Composable`).
- Booleans read as questions: `isLoading`, `canStart`, `hasReachedDestination`,
  `showProfileSheet` for visibility flags. Never a bare noun. (Detekt's
  `BooleanPropertyNaming` is off, so this one is review-enforced.)
- Per-feature types: see the MVI naming above. Koin modules: `<feature>Module` /
  `<feature>UiModule` in `di/<Feature>Module.kt`.
- Test names are backtick sentences (`` `saves activity with recalculated calories`() ``),
  never `test1`. See `tm-testing`.

## No deprecated APIs (Kotlin)

- Never call anything marked `@Deprecated`, including AndroidX/Compose/Material APIs
  deprecated in the current BOM. Use the documented replacement (for example
  `Icons.AutoMirrored.Filled.DirectionsRun`, not `Icons.Filled.DirectionsRun`).
- `allWarningsAsErrors = true` enforces this in every Kotlin module, `androidApp/*` included.
  The root `build.gradle.kts` sets it for `androidApp/*` via
  `plugins.withId("com.android.application")` / `plugins.withId("com.android.library")`
  configuring `KotlinAndroidProjectExtension`. Those modules use AGP 9 built-in Kotlin, so
  AGP registers the `kotlin` extension itself and `org.jetbrains.kotlin.android` is never
  applied (hooking on that id is what left the flag off before). KMP modules are covered by
  the separate `org.jetbrains.kotlin.multiplatform` block. Any compiler warning, including
  a deprecation or an unacknowledged `@RequiresOptIn` warning, fails the build.
- Experimental APIs (`@RequiresOptIn`, e.g. maps-compose's `MapsComposeExperimentalApi`)
  also warn. If there's no stable alternative, opt in as narrowly as possible, at the call
  expression or the smallest enclosing declaration, with a comment saying why (see
  `MapEffect` in `TrackingScreen.kt`). Never opt in module-wide via `optIn` compiler options.
- If a deprecation is genuinely unavoidable (a third-party library with no replacement
  yet), suppress it narrowly at the call site with `@Suppress("DEPRECATION")` and a comment
  stating why. Never suppress at file or module level.
- Don't mark your own APIs `@Deprecated` to phase them out. Update the callers and delete
  the old API in the same change.

## No dead code

- No commented-out code in a commit. Git history is the backup.
- No unused private functions, properties, classes or parameters left behind after a
  refactor. Detekt's `UnusedPrivateMember`/`UnusedPrivateProperty`/`UnusedPrivateClass`/
  `UnusedParameter` catch the private ones. Unused `internal`/`public` code and unused
  imports (`UnusedImports` is off) are not caught, so check them yourself.
- Explanatory comments on *why* are welcome (see `MainActivity`'s `stopTrackingRequested`
  and `trackingUiModule`'s `CalorieCalculator` note). Commented-out code is not.

## Module boundaries

Full rules live in `tm-kmp-shared`; load it before touching `domain`/`data`/`core`/`shared`.
The Android-relevant parts:
- Nothing in `domain` imports `android.*`, `androidx.*` or Compose. Nothing in `core`'s
  `commonMain` imports any UI framework. Compose goes in `androidApp/core-ui`, never `core`.
- `shared` is the only module that `export()`s Kotlin to iOS.
- Feature modules stay off `:data`/`:shared` and off each other (see Architecture).
- If a task seems to need crossing one of these, stop and report it. Don't work around it.

## Detekt (CI-enforced, `maxIssues: 0`)

Config: `config/detekt/detekt.yml`, applied to every subproject by the root
`build.gradle.kts` with `buildUponDefaultConfig = true` and `autoCorrect = true`. Run it
with `./gradlew detekt`. It is part of the local pre-push gate
(`scripts/pre-push-check.sh`) and CI.

- Forbidden: `println`/`print` (`ForbiddenMethodCall`, use a logger) and any
  `kotlinx.coroutines.GlobalScope` import (`ForbiddenImport`, use `viewModelScope` or an
  injected scoped `CoroutineScope`).
- Thresholds: `LongMethod` 60 lines, `CyclomaticComplexMethod` 15 (both ignore
  `@Composable` functions but apply everywhere else), `TooManyFunctions` 12 per class,
  `LongParameterList` 7 for functions and constructors (`TrackingViewModel.kt` is
  excluded). Default `MaxLineLength` is 120. `MagicNumber` and `ReturnCount` are off.
- `!!` is not banned by tooling but is rejected in review. Use `checkNotNull(x) { "why" }`,
  or restructure so the nullable type never reaches that point.
- Don't add excludes to `config/detekt/detekt.yml` and don't add `@Suppress` to make a
  violation pass. Refactor instead, or ask if the rule genuinely doesn't fit. Any
  suppression needs explicit human approval and a comment with the reason.

## Tests

Test code follows `tm-testing`, which has the rest. In short: JUnit4 with `kotlin.test`
assertions, `kotlinx-coroutines-test` and hand-written fakes for Android tests (MockK is not
in the catalog), and compose-ui-test for Compose UI tests; `kotlin.test` + hand-written fakes
in `domain`; no Truth, no JUnit5; `UnconfinedTestDispatcher` unless a test needs to control
dispatch order; Robolectric only when a test genuinely needs the Android framework. The three
feature modules have JVM test source sets, sharing fakes via `androidApp/core-testing`. Truth
was removed in #32.

## Known deviations in the current code

Don't copy these as a pattern for new code.
- Each screen file also has a public `<X>Screen(...)` overload that only delegates to
  `<X>Root`, kept so `MainActivity`'s NavHost call sites didn't change. It shares its name
  with the stateless `<X>Screen(state, onAction, ...)`.
- `MainActivity` field-injects with `by inject()` (see Koin).
- The existing `@Suppress("UnusedPrivateMember")` and
  `@Suppress("LocalContextGetResourceValueCall")` in `RouteScreen.kt`/`TrackingScreen.kt`
  carry no reason comment. New suppressions need one.
