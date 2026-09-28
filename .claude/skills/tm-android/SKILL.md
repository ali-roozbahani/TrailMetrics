---
name: tm-android
description: Use when writing or changing Android code in TrailMetrics under androidApp/ — Compose screens, ViewModels, Koin wiring, feature modules. Covers the MVI target shape for ViewModels, Compose conventions, Koin registration, and Gradle module setup. Not for domain/data/core/shared (see tm-kmp-shared) or for test code (see tm-testing).
---

# TrailMetrics Android

## Presentation layer — MVI (target shape; migration in progress)

Every screen has:
1. **State** — one data class with all UI state fields.
2. **Action** — sealed interface of user-triggered actions, entry point `onAction(Action)`.
3. **Event** — sealed interface of one-time side effects (navigation, snackbar), delivered
   via `Channel`, never a plain callback lambda.
4. **ViewModel** — `StateFlow<State>` + `onAction()`, no other public methods.

This replaces the current pattern seen in `TrackingViewModel.kt` (public methods like
`onStartClicked()`, `onPauseClicked()`, and a callback parameter `onFinishClicked(path,
onSaved: () -> Unit)`). When migrating a ViewModel:
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
- One Koin module per feature (`trackingUiModule`, `routeModule`, `historyUiModule`),
  defined in that feature's own package, registered in
  `initKoin { modules(...) }` inside `TrailMetricsApplication.onCreate()`.
- Prefer `viewModelOf(::MyViewModel)` / `singleOf(::Impl)` constructor-reference form.
  Only fall back to the lambda form (`viewModel { ... }`) when you need a factory
  method, a qualifier, or post-construction setup.
- Cross-platform bindings (anything iOS also needs via `KoinHelper`) go in `shared`/
  `data`, not here — see `tm-kmp-shared`.
- Always inject ViewModels with `koinViewModel()` in the Root composable. Never pass a
  ViewModel down the composable tree.

## Compose

- The UI is dumb: composables render `state` and forward `Action`s via `onAction`.
  Zero business logic, zero data transformation in composables.
- State lives in the ViewModel's `StateFlow`, collected with
  `collectAsStateWithLifecycle()`. `remember`/`rememberSaveable` are only for
  Compose-owned state the framework requires you to hold in composition
  (`LazyListState`, `ScrollState`) — not for application state.
- Animate below the recomposition layer: `graphicsLayer`, offset lambdas, or
  `animateFloatAsState` feeding into `graphicsLayer` — not `Modifier.alpha(animatedValue)`
  directly.
- Every Screen composable gets at least one `@Preview` with realistic sample state,
  wrapped in the app theme.
- Meaningful `contentDescription` (via string resources) on interactive/informational
  elements; `null` for purely decorative ones.

## Module / Gradle conventions

New feature modules follow the existing `androidApp/feature-tracking`-style layout:
`com.android.library` + `org.jetbrains.kotlin.plugin.compose` plugins, `compileSdk 37`,
`minSdk 26`, Java 11 source/target compatibility, dependencies on `:domain`, `:core`,
`:androidApp:core-ui`, plus the Compose BOM and Koin BOM (see an existing module's
`build.gradle.kts` for the exact block — copy its structure, don't hand-roll a new one).
All versions come from `libs.versions.toml` — never hardcode a version in a module's
`build.gradle.kts`.

## Detekt (CI-enforced, `maxIssues: 0`)

No `println`/`print`, no `GlobalScope`. `LongMethod`/`CyclomaticComplexMethod` are
relaxed for `@Composable` functions but still apply everywhere else. Don't add new
excludes to `config/detekt.yml` to make a violation pass — refactor instead, or ask
if the rule genuinely doesn't fit the situation.
