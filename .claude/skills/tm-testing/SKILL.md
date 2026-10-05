---
name: tm-testing
description: Use whenever writing or reviewing tests anywhere in TrailMetrics — domain, data, ViewModel/MVI, or Compose UI tests, on Android or in commonTest/KMP code. Fixes the testing stack (JUnit4 for Android, kotlin.test for KMP and assertions, hand-written fakes; MockK/Turbine are intended but not yet in the catalog; no Truth, no JUnit5) and testing patterns per layer. Not for the code under test itself — see tm-kmp-shared or tm-android for that.
---

# TrailMetrics testing

## Stack (fixed — do not introduce an alternative without being asked)

| Layer | Framework | Assertions | Mocking |
|---|---|---|---|
| `domain`, other commonTest/KMP | `kotlin.test` | `kotlin.test` (`assertEquals`, `assertTrue`, ...) | fakes, not mocks — MockK has no Kotlin/Native artifact |
| `data`, Android-framework code (Robolectric, Compose), Android ViewModels | JUnit4 | `kotlin.test` | hand-written fakes today; MockK once added (see below) |
| `data` HTTP-level tests (commonTest) | `kotlin.test` | `kotlin.test` | Ktor `MockEngine` (`ktor-client-mock`) serving a canned response to the real repository |

### What's actually available today

MockK and Turbine are the intended additions for Android-side tests, but **neither is in
`gradle/libs.versions.toml` and no module depends on either** (checked 2026-09-29; no
file in the repo imports `io.mockk` or `app.cash.turbine`). CLAUDE.md forbids adding a
third-party dependency the task doesn't name, so until a task explicitly adds them:

- Android ViewModel/MVI tests use JUnit4 + `kotlin.test` + `kotlinx-coroutines-test` +
  hand-written fakes. All three libraries are already catalog entries (`junit`,
  `kotlin-test`, `kotlinx-coroutines-test`).
- Flow assertions read `StateFlow.value` after driving the test scheduler, or collect
  into a list from `backgroundScope` (see "Coroutines / Flow"). Don't use Turbine's
  `.test { awaitItem() }`.
- `feature-route`, `feature-history` and `feature-tracking` already have JVM test source
  sets with `testImplementation` lines for those catalog entries plus
  `:androidApp:core-testing`. A new Android module's first test adds the same lines to
  its own `build.gradle.kts`. That is not a new dependency.
- Compose UI tests run on the JVM under Robolectric, inside the module's `testDebugUnitTest`
  (no emulator, no `androidTest`). `feature-history` is the first feature module with them:
  its `build.gradle.kts` adds the catalog entries `robolectric`, `androidx-compose-ui-test-junit4`
  and `androidx-compose-ui-test-manifest` (with `platform(libs.androidx.compose.bom)` for their
  versions) as `testImplementation`, plus `testOptions.unitTests.isIncludeAndroidResources = true`
  so tests can read string resources. `feature-route` and `feature-tracking` don't have them
  yet; their first Compose UI test adds the same lines. See "Compose UI tests".
- A task that adds MockK or Turbine must name it, add it to the catalog, and update this
  section in the same change.
- Ktor `MockEngine` (`ktor-client-mock`, on the catalog's `ktor` version) is a `data`
  commonTest dependency, so it runs on the Android host and the iOS simulator. Build the
  real repository on `HttpClient(MockEngine { respond(...) })` with the same
  `ContentNegotiation`/`Json` setup as `networkModule`, and return JSON shaped like the
  DTO (see `DirectionsRepositoryImplTest`). Don't fake `HttpClient` or the repository.

No JUnit5 anywhere in this project (evaluated and rejected — see
`docs/architecture` for the reasoning if resurrected later). No AssertK. No Truth (removed
from `data`, its only prior user; no `com.google.truth` import remains).

## Coroutines / Flow

```kotlin
class TrackingSessionManagerTest {
    private val testDispatcher = UnconfinedTestDispatcher()

    @Before
    fun setUp() { Dispatchers.setMain(testDispatcher) }

    @After
    fun tearDown() { Dispatchers.resetMain() }
}
```

(`@Before`/`@After` — JUnit4 annotations, not JUnit5's `@BeforeEach`/`@AfterEach`.)

For a `StateFlow`, drive the scheduler and assert on `.value`. This is what
`domain/src/commonTest/.../tracking/TrackingSessionManagerTest.kt` does:

```kotlin
@Test
fun `start transitions to Tracking`() = runTest(testScheduler) {
    manager.start(point1)
    testScheduler.runCurrent()

    assertIs<TrackingState.Tracking>(manager.currentState.value)
}
```

For a one-shot stream (a `Channel`-backed `events` flow, a `SharedFlow`), or a `StateFlow`
built with `stateIn(WhileSubscribed)` that needs a subscriber, collect from
`backgroundScope`. It is cancelled automatically when the test ends:

```kotlin
val events = mutableListOf<RouteEvent>()
backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.events.toList(events) }
```

Turbine (`.test { awaitItem() }`) replaces both once a task adds it (see "What's actually
available today").

## Fakes over mocks in `domain`

`domain` tests use hand-written fakes implementing the repository interfaces (no MockK
in commonTest). Keep fakes minimal and controllable:

```kotlin
class FakeLocationRepository : LocationRepository {
    private val updates = MutableSharedFlow<LocationUpdate>(extraBufferCapacity = 1)
    override fun observeLocationUpdates(): Flow<LocationUpdate> = updates
    fun emit(update: LocationUpdate) = updates.tryEmit(update)
}
```

Android-only tests (ViewModels, repositories) use fakes too, since MockK isn't available
yet. The fakes in `domain/src/commonTest/.../fakes/` aren't visible to other modules.
Android feature tests share theirs through `androidApp/core-testing` (consumed only via
`testImplementation`, never `implementation`/`api`; see its `README.md`):
- Before writing a fake or fixture for a ViewModel test, check `core-testing` for an
  existing one and use it.
- Put a new fake there when a second feature module will plausibly need it (typically a
  fake of a `domain` repository interface). A fake only one feature needs stays in that
  feature's `src/test/.../fakes/`.

iOS's equivalent is `iosApp/Packages/TestSupport`. Only interfaces can be faked this way.
Concrete classes such as the use cases and `TrackingSessionManager` are final. Build the
real class around fakes of its interface collaborators (`TrackingSessionManager` from a
fake `LocationRepository`, `TrackingServiceLauncher`, `Clock` and `Logger` plus a
`TestScope`, as the domain test does). That way ViewModel tests drive real state
transitions instead of stubbing return values. Once MockK is added, it's fine for
collaborators that are tedious to fake, but a fake stays preferred for anything with real
behavior worth exercising.

## Testing MVI ViewModels

Write the test against `onAction()` and the resulting `state`/`event` stream — never
against the old per-action public methods once a screen has been migrated to MVI
(see `tm-android`). Test-first when migrating: write the `onAction`-based test against
the desired State/Action/Event shape before changing the ViewModel implementation, so
the test both specifies and locks the target behavior.

```kotlin
@Test
fun `Pause action pauses an active tracking session`() = runTest(testScheduler) {
    // sessionManager: a real TrackingSessionManager built from fakes (see "Fakes over mocks")
    val viewModel = TrackingViewModel(sessionManager, fakeProfileRepo, CalorieCalculator(), saveActivityUseCase, ActivityType.Running, emptyList(), fakeClock)
    // state is stateIn(WhileSubscribed): keep a subscriber for the whole test
    backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.state.collect {} }

    viewModel.onAction(TrackingAction.Start(someCoordinates))
    testScheduler.runCurrent()
    assertIs<TrackingState.Tracking>(viewModel.state.value.trackingState)

    viewModel.onAction(TrackingAction.Pause)
    testScheduler.runCurrent()
    assertIs<TrackingState.Paused>(viewModel.state.value.trackingState)
}

@Test
fun `Finish action emits Saved event on success`() = runTest(testScheduler) {
    val viewModel = TrackingViewModel(/* session manager driven to Finished */ ...)
    val events = mutableListOf<TrackingEvent>()
    backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.events.toList(events) }

    viewModel.onAction(TrackingAction.Finish(snapshotFilePath = null))
    testScheduler.advanceUntilIdle()

    assertEquals(listOf<TrackingEvent>(TrackingEvent.Saved), events)
}
```

`viewModelScope` runs on `Dispatchers.Main`, so these tests also need the
`Dispatchers.setMain(...)`/`resetMain()` setup from "Coroutines / Flow", using a
dispatcher on the same `testScheduler`.

## Bugfixes: red test first

A bugfix starts with a test that reproduces the defect. Run it on the unfixed code and see it
fail for the right reason (the defect, not a compile error or a setup problem), and commit it
before or together with the fix. Put the red evidence in the PR: the test name and its failure
message. A pinned "currently ..." test of a known defect is rewritten to assert the correct
behavior when the defect is fixed, not deleted.

## Compose UI tests

`ComposeTestRule`, JUnit4 (`@get:Rule`). Use the Robot pattern once a screen has 3+ UI
test cases or several tests share setup/assertion sequences — one robot class per
screen, every method returns `this` for chaining:

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

Don't reach for the robot pattern for a 1-2 assertion smoke test — plain
`composeTestRule.setContent { ... }` + a couple of `onNodeWith...` calls is clearer there.

### Screen tests through the real ViewModel (the pattern to copy)

`feature-history`'s `DetailsScreenTest`/`HistoryScreenTest` (with `DetailsScreenRobot`/
`HistoryScreenRobot`) are the reference. What they do:

- `@RunWith(RobolectricTestRunner::class)`, `@Config(sdk = [35])` (as in `data`; add
  `qualifiers = "w411dp-h891dp"` when a `LazyColumn` must compose several rows), and
  `createAndroidComposeRule<ComponentActivity>()`, so strings come from
  `rule.activity.getString(...)` instead of being copied into the test.
- Test the `<X>Root`, not only the stateless `<X>Screen`, so event handling (navigation
  callback, snackbar) is covered. In `@Before`: `Dispatchers.setMain(UnconfinedTestDispatcher(...))`
  and `startKoin { modules(<feature>UiModule, module { /* fakes from core-testing */ }) }`;
  in `@After`: `stopKoin()` and `resetMain()`. `koinViewModel()` then builds the real ViewModel.
  Navigation lives in `androidApp/app`, so assert on the Root's callback (count its calls).
- Hold a suspending call with the fake's gate (`deleteActivityGate`, `getActivityGate`, ...:
  a `CompletableDeferred` the fake awaits). Act, assert nothing happened yet, `complete(Unit)`,
  `rule.waitForIdle()`, assert. No `Thread.sleep`, no real delays.
- Double tap: `performTouchInput { down(center); up(); down(center); up() }`. The injector
  advances the main clock by the time between events (whatever `autoAdvance` is), and
  `click()` includes a move that takes time, so `click(); click()` lets the first tap's
  recomposition remove the button and the second tap hits nothing: the test passes with or
  without the guard. Check it once by removing the guard in the working tree: the test must
  fail on the doubled call (for `DetailsScreenTest`: `Expected <[1]>, actual <[1, 1]>.`).
- Maps: wrap the content in `CompositionLocalProvider(LocalInspectionMode provides true)`.
  maps-compose's `GoogleMap` then draws an empty `Box`, so no Maps SDK runs on the JVM; the
  map's content (polylines, markers) is not tested. No production seam is needed for it.
- Find nodes by visible text and content description first; a `testTag` is a production
  change, so only when nothing else identifies the node. A merged node (a clickable `Card`)
  matches every text inside it: assert a row with `hasText(a) and hasText(b) ...`.

## What to test, and coverage priorities (current state: measured, uneven)

The merged Kover report (see `tm-pr-workflow`, Tier 1) shows real line coverage for `domain`
(high), the three Android feature modules (partial) and `data` (partial: its Room repository suite
runs on the Android host via Robolectric; the directions repository, `safeApiCall`, the directions
DTOs and the polyline decoder have commonTest tests, the repository's on `mockHttpClient`; location,
`TrackingService` and DI have no tests). `core`, `shared`, `androidApp/app` and
`androidApp/core-ui` have no tests of their own. `domain`, `data` and the feature modules have
a `koverVerify` minimum, so adding untested code there can fail the gate. When asked to raise
coverage without a more specific target, prioritize in this order:
1. `domain`: pure logic first — `CalorieCalculator`, speed/Haversine calculations,
   `TrackingSessionManager`'s state transitions (`UpdateTrackingStateUseCase`), use
   cases like `SaveActivityUseCase`.
2. `data`: repository implementations, especially anything with offline/fallback logic.
3. ViewModels: all four Android ViewModels are on MVI and have `onAction`-based tests.
   New or changed ViewModel behavior gets a test against `onAction` and the resulting
   `state`/`events` (see above).
4. Compose UI tests: after a screen's ViewModel and Action/Event shape are stable.

## Detekt / CI note

`./gradlew test` runs zero KMP tests; the gate runs `allTests test`. After any test-framework
or dependency change, compare test counts before and after with the method in `tm-pr-workflow`
("PR description", Tier 1 item): per module and per target, from the JUnit XML. A silent drop
to zero discovered tests in one task is the failure mode to watch for, not just a red/green
result.
