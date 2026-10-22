# Compose UI tests: examples and setup

Read from `SKILL.md`, "Compose UI tests". The rules are there; this file holds the example and the
setup details behind them.

## Robot example

One robot class per screen, every method returns `this` for chaining:

```kotlin
class TrackingScreenRobot(private val rule: ComposeContentTestRule) {
    fun setContent(state: TrackingState, onAction: (TrackingAction) -> Unit = {}) = apply {
        rule.setContent { TrackingScreen(state = state, onAction = onAction) }
    }
    fun assertStartButtonEnabled() = apply {
        rule.onNodeWithTag("start_button").assertIsEnabled()
    }
    fun clickStart() = apply {
        rule.onNodeWithTag("start_button").performClick()
    }
}
```

## Screen tests through the real ViewModel

`feature-history`'s `DetailsScreenTest`/`HistoryScreenTest` (with `DetailsScreenRobot`/
`HistoryScreenRobot`) are the reference.

- Runner and rule: `@RunWith(RobolectricTestRunner::class)`, `@Config(sdk = [35])` (as in `data`;
  add `qualifiers = "w411dp-h891dp"` when a `LazyColumn` must compose several rows), and
  `createAndroidComposeRule<ComponentActivity>()`.
- Setup: the `<X>Root` is tested, so event handling (navigation callback, snackbar) is covered.
  In `@Before`: `Dispatchers.setMain(UnconfinedTestDispatcher(...))` and
  `startKoin { modules(<feature>UiModule, module { /* fakes from core-testing */ }) }`; in
  `@After`: `stopKoin()` and `resetMain()`. `koinViewModel()` then builds the real ViewModel.
  Navigation lives in `androidApp/app`, so assert on the Root's callback (count its calls).
- Gates: the fake's gate (`deleteActivityGate`, `getActivityGate`, ...) is a `CompletableDeferred`
  the fake awaits. Act, assert nothing happened yet, `complete(Unit)`, `rule.waitForIdle()`, assert.

## Double tap

`performTouchInput { down(center); up(); down(center); up() }`. The injector advances the main
clock by the time between events (whatever `autoAdvance` is), and `click()` includes a move that
takes time, so `click(); click()` lets the first tap's recomposition remove the button and the
second tap hits nothing: the test passes with or without the guard. The check in the working tree
(remove the guard, the test must fail on the doubled call) shows for `DetailsScreenTest`:
`Expected <[1]>, actual <[1, 1]>.`

## Maps

- **No map callback needed.** Wrap the content in `CompositionLocalProvider(LocalInspectionMode
  provides true)`, as the Route, Details and Tracking robots do. maps-compose's `GoogleMap` then
  draws an empty `Box`, so no Maps SDK runs on the JVM; the map's content (polylines, markers) is
  not tested. No production seam is needed for it.
- **Map callback driven** (`MapEffect`, `GoogleMap.snapshot { }`). Render the map, as
  `feature-tracking`'s `TrackingScreenSnapshotTest` does with test sources only
  (`src/test/.../fakes/FakeGoogleMap.kt`):
  - `@Config(shadows = [ShadowMapView::class])` replaces `MapView` with a Robolectric shadow (it
    must extend `ShadowViewGroup`, the shadow of its superclass chain) whose `getMapAsync` answers
    at once with a real `GoogleMap` over `FakeGoogleMap`'s `Proxy` delegate.
  - The test sets `FakeGoogleMap.current` before composing and composes with `LocalInspectionMode`
    false.
  - Every delegate call returns a default except `snapshot`, whose callback the test delivers with
    `deliverSnapshot(...)`.
  - The map's content is still not asserted. The camera and bitmap-descriptor factories are fakes
    installed by `FakeGoogleMap.installFactories()`; they are static, so a test that renders no map
    and must see an uninitialized Maps SDK (`TrackingScreenTest`) calls
    `FakeGoogleMap.uninstallFactories()` first. `TrackingScreen` builds its camera update only
    once the map exists.
