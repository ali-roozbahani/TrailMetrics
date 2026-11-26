---
name: tm-android
description: Use when writing or changing Android code in TrailMetrics under androidApp/ — Compose screens, ViewModels, Koin wiring, feature modules, core-ui. Covers the MVI target shape for ViewModels, Compose conventions, Koin registration, Gradle module setup, Kotlin naming/deprecation/dead-code rules and Detekt. Not for domain/data/core/shared (see tm-kmp-shared) or for test code (see tm-testing).
---

# TrailMetrics Android

This skill is the source of truth for Android conventions (it replaced the retired
`android_developer_guide.md` and `shared_conventions.md`). It records both the rules and what
the current code under `androidApp/` actually does. Where they differ, the code wins for "what
exists", this skill's MVI section wins for "what new ViewModels should look like".

## Topic files

Read each file when the task or the diff reaches its topic, not before; a reviewer reads it for a diff that touches the
topic. Section headings are unchanged, so a reference to `tm-android`, "<heading>", is found in this file or in the file
named here.

| File | Read it when |
|---|---|
| `koin-and-gradle.md` ("Koin", "Module / Gradle conventions") | a change registers or changes a Koin module or a `viewModel`/`single` binding, adds a feature module, or edits a `build.gradle.kts`, `settings.gradle.kts` or `libs.versions.toml` under `androidApp/` |
| `kotlin-conventions.md` ("Naming (Kotlin)", "No deprecated APIs (Kotlin)", "No dead code", "Detekt") | a change names a new class, function, module or package, replaces or suppresses a deprecated call or an opt-in, removes code, or a Detekt step fails; also read by `tm-kmp-shared` for the same Kotlin rules |


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
- A ViewModel holds presentation state only: it never touches a DAO, file, HTTP client or
  `Context`, and holds no formatting or business rule that belongs in `domain` (`tm-kmp-shared`,
  "Where logic lives"). Enforced: reviewer only. Violation: `blocking` for data access, `important`
  for a misplaced rule.
- Dependencies are constructor-injected and typed to the `domain` interface
  (`ActivityHistoryRepository`), never to its `data` implementation. Enforced: the module graph (a
  feature module cannot see `:data`); reviewer only elsewhere. Violation: `blocking`.
- One reason to change per class. Enforced: detekt `TooManyFunctions` and `LongParameterList` (see
  "Detekt", `kotlin-conventions.md`) are the mechanical signal; a class that mixes state, IO and formatting is the judgement
  one, reviewer only. Violation: `important`.
- Never an `is`/`as` cast on an abstraction to reach a concrete type, and never an interface method
  that an implementer leaves empty or throws `NotImplementedError` from (split the interface).
  Enforced: reviewer only. Violation: `important`.
- Crashes, ANR, exceptions, threads, process death, leaks and performance: `tm-robustness`.
- `AppRoute` lives in `core`'s `commonMain` and is the single source of destinations. Never
  recreate a local route sealed class in a feature module.
- `RouteUiError` (in `core`) is the shared error classification. Its Android-only
  `stringRes` mapping lives in `androidApp/core-ui`'s `error/RouteUiErrorAndroid.kt`. A new
  `RouteUiError` case needs a branch there (plus the string in `core-ui`'s `strings.xml`) in
  the same change. The `when` is exhaustive, so the build fails if you forget.
- A `when` over a sealed type or an enum names every case and has no `else`: `tm-kmp-shared`,
  "Exhaustive `when` over a sealed type".
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

**Current code:** all four ViewModels follow this shape: `val state: StateFlow<<X>State>`,
`val events: Flow<<X>Event>` backed by a `Channel`, one public `onAction(<X>Action)`; each screen
file has a `<X>Root` (`koinViewModel()`, collects events) and a stateless `<X>Screen(state,
onAction, ...)`. `HistoryViewModel` is a reference for a new screen (`TrackingViewModel`'s state is
`TrackingScreenState`, to avoid the domain `TrackingState` clash below). Don't copy from a
ViewModel that is not on this shape; computed properties on the state (`canStart`, ...) may stay
`State` getters.

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

## Compose

- The UI is dumb: composables render `state` and forward `Action`s via `onAction`.
  Zero business logic, zero data transformation in composables. Logic like route
  progress/completion belongs in `domain`, as iOS needs it too: `TrackingSessionManager`
  owns the route-end rule and `routeProgress`; `TrackingViewModel` only puts the manager's
  `routeProgress` into its state, and the finish card follows `canSave`.
- Stateless and hoisted: a composable takes state as parameters and reports changes through
  lambdas. Below the Root, no composable reads a ViewModel; pass data down.
- State lives in the ViewModel's `StateFlow`, collected with
  `collectAsStateWithLifecycle()`. `remember`/`rememberSaveable` are only for view-local UI
  state that business logic never needs: Compose-owned holders (`rememberLazyListState()`, which keeps
  the scroll position through recreation, never `remember { LazyListState() }`; `SnackbarHostState`,
  `rememberCameraPositionState()`), dialog/sheet visibility
  (`showDeleteConfirmation`), or a text-field draft before it's submitted (`weightInput`).
  Anything that business logic reads belongs in the ViewModel. A ViewModel does not survive process
  death: what the user would lose is also in `SavedStateHandle` or persisted (`tm-robustness`, R1).
- Collect events in a `LaunchedEffect` in the Root, with an exhaustive `when`.
- A `LaunchedEffect` or `DisposableEffect` that lives across recompositions and calls a callback
  parameter reads the latest callback through `rememberUpdatedState`, or has that callback as its key.
  State a composable owns is `remember`ed, never `mutableStateOf(...)` as a default argument. Why: an
  effect keyed by `Unit` keeps calling the first callback it captured, and a default argument is built
  again on every call, so the state is lost on recomposition. Example: `HistoryRoot`. Enforced:
  reviewer only. Severity: important. Not a finding: an effect that calls no parameter, or reads only
  the values it is keyed by.
- A reusable composable (used by more than one screen, or in `core-ui`) takes `modifier: Modifier =
  Modifier` as its first optional parameter, after the required ones, and applies it to its root
  element. Why: the caller decides size, padding and placement. Example: `MetricCell`. Enforced: reviewer
  only. Severity: important. Not a finding: a `<X>Root` or `<X>Screen` composable, which navigation calls
  once.
- Animate below the recomposition layer: `graphicsLayer`, offset lambdas, or
  `animateFloatAsState` feeding into `graphicsLayer` — not `Modifier.alpha(animatedValue)`
  directly. Each branch of an `AnimatedContent` draws from its own target parameter, not from state
  read outside the lambda, so the outgoing branch does not change while it fades out. Enforced:
  reviewer only. Severity: important.
- Insets: the app is edge-to-edge (`enableEdgeToEdge()`, target SDK 37). A `Scaffold`'s `innerPadding`
  goes to the scrollable's `contentPadding` (added to its own spacing), never as `Modifier.padding` on a
  parent around the list, so the list scrolls under the bars. Apply the keyboard insets once: not both
  `contentWindowInsets` with the IME and `imePadding()` on the same content. A screen with a text field
  needs a human check that the keyboard does not cover it (Tier 2, `tm-pr-workflow`).
- No `android:configChanges` and no `android:screenOrientation` in the manifest to avoid recreation: state
  that a recreation loses is fixed by R1 of `tm-robustness`, not by suppressing the recreation.
- Every new Screen composable gets at least one `@Preview` with realistic sample state,
  wrapped in `TrailMetricsTheme`. A preview doesn't replace running the app. Each of the
  four screens has one (`RouteScreenPreview`, `TrackingScreenPreview`,
  `HistoryScreenPreview`, `DetailsScreenPreview`; `RouteScreen.kt` also has
  `ActivityTypeSelectorPreview`). Follow the four screen previews' form: a `private`
  function with `@Suppress("UnusedPrivateMember")`, because Detekt counts it as unused,
  and a one-line comment saying so.
- Meaningful `contentDescription` (via string resources, `cd_*` keys) on
  interactive/informational elements; `null` for purely decorative ones.
- No user-visible text in Kotlin: every text the user reads (a `Text`, a `contentDescription`, a snackbar, a
  dialog, a notification's title, text and channel name) comes from a string resource (`R.string`) of the
  module that shows it, never a literal, and a formatted text uses format arguments (`%1$s`), never
  concatenation. A value from `domain` or `data` arrives typed and the module maps it to its resources (as
  `RouteUiError.stringRes` does). The project-wide rule: `tm-kmp-shared`, "User-visible text". Enforced:
  reviewer only. Severity: blocking for a new text.
- Colors and typography come from `core-ui`'s `designsystem/theme`; no ad-hoc color
  literals in features.

## Module boundaries

Full rules live in `tm-kmp-shared`; load it before touching `domain`/`data`/`core`/`shared`.
The Android-relevant parts:
- Nothing in `domain` imports `android.*`, `androidx.*` or Compose. Nothing in `core`'s
  `commonMain` imports any UI framework. Compose goes in `androidApp/core-ui`, never `core`.
- `shared` is the only module that exports production API to iOS (`shared-uitest` builds only a
  test-only variant of the same framework, linked by UI-test builds alone; ADR-002).
- Feature modules stay off `:data`/`:shared` and off each other (see Architecture).
- The dependency direction is presentation to `domain` to nothing; `data` implements `domain`
  interfaces and `domain` never imports a `data` type. Enforced: the Gradle module graph (a wrong
  `project(...)` line fails review of the build file); reviewer only for an import inside a module.
  Violation: `blocking`.

## Tests

Test code follows `tm-testing` (stack, fakes, `core-testing`, Robolectric, Compose UI tests). Use
`UnconfinedTestDispatcher` unless a test needs to control dispatch order. Robolectric only when a
test genuinely needs the Android framework.

## Known deviations in the current code

Don't copy these as a pattern for new code.
- Each screen file also has a public `<X>Screen(...)` overload that only delegates to
  `<X>Root`, kept so `MainActivity`'s NavHost call sites didn't change. It shares its name
  with the stateless `<X>Screen(state, onAction, ...)`.
- `MainActivity` field-injects with `by inject()` (see "Koin", `koin-and-gradle.md`).
- The `AnimatedContent` in `TrackingScreen` reads `canStart`, `canPause`, `canResume` and `canStop` from
  the outer state in its `else` branch. No test shows the fade overlap this can cause, so the branch is
  as it is (the animation rule in "Compose").
- `TrackingViewModel.events` is not only its `Channel`: it merges the manager's `locationIssues` `SharedFlow` and
  the unsaved-session warning's `isRaised` `StateFlow` (as `ShowSessionNotSaved` to every collector while it is
  raised, until the Root sends `SessionNotSavedShown`). A new screen sends its own events through its `Channel`.
- `TrackingService`'s foreground notification and `RestoredNotification`'s title are Kotlin literals in `data`
  (board: `android-tracking-notification-text-in-code`).
