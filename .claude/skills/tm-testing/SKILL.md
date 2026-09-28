---
name: tm-testing
description: Use whenever writing or reviewing tests anywhere in TrailMetrics — domain, data, ViewModel/MVI, or Compose UI tests, on Android or in commonTest/KMP code. Fixes the testing stack (JUnit4 + MockK for Android, kotlin.test for KMP, no Truth, no JUnit5) and testing patterns per layer. Not for the code under test itself — see tm-kmp-shared or tm-android for that.
---

# TrailMetrics testing

## Stack (fixed — do not introduce an alternative without being asked)

| Layer | Framework | Assertions | Mocking |
|---|---|---|---|
| `domain`, other commonTest/KMP | `kotlin.test` | `kotlin.test` (`assertEquals`, `assertTrue`, ...) | fakes, not mocks — MockK has no Kotlin/Native artifact |
| `data`, Android-framework code (Robolectric, Compose) | JUnit4 | `kotlin.test` | MockK |

No JUnit5 anywhere in this project (evaluated and rejected — see
`docs/architecture` for the reasoning if resurrected later). No AssertK. No Truth —
being actively removed from `data`, its only prior user; if a task touches a file
still importing `com.google.truth.Truth`, migrate that file's assertions to
`kotlin.test` as part of the change rather than leaving it mixed.

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

Use Turbine for `StateFlow`/`SharedFlow` assertions:

```kotlin
@Test
fun `starting tracking transitions Idle to Tracking`() = runTest {
    val manager = TrackingSessionManager(fakeLocationRepo, useCase, fakeLauncher, speedCalc, fakeClock, logger, this)

    manager.currentState.test {
        assertEquals(TrackingState.Idle, awaitItem())
        manager.start(someCoordinates)
        assertTrue(awaitItem() is TrackingState.Tracking)
    }
}
```

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

In Android-only tests (ViewModels, repositories), MockK is fine for collaborators that
are tedious to fake, but prefer a fake for anything with real behavior worth exercising
(e.g. a fake `TrackingSessionManager` backed by a `MutableStateFlow`, so ViewModel tests
drive real state transitions instead of stubbing return values).

## Testing MVI ViewModels

Write the test against `onAction()` and the resulting `state`/`event` stream — never
against the old per-action public methods once a screen has been migrated to MVI
(see `tm-android`). Test-first when migrating: write the `onAction`-based test against
the desired State/Action/Event shape before changing the ViewModel implementation, so
the test both specifies and locks the target behavior.

```kotlin
@Test
fun `Pause action pauses an active tracking session`() = runTest {
    val viewModel = TrackingViewModel(fakeSessionManager, fakeProfileRepo, calorieCalc, fakeSaveUseCase, ActivityType.Running, emptyList(), fakeClock)

    viewModel.state.test {
        awaitItem() // initial
        viewModel.onAction(TrackingAction.Start(someCoordinates))
        assertTrue(awaitItem().trackingState is TrackingState.Tracking)
        viewModel.onAction(TrackingAction.Pause)
        assertTrue(awaitItem().trackingState is TrackingState.Paused)
    }
}

@Test
fun `Finish action emits Saved event on success`() = runTest {
    val viewModel = TrackingViewModel(/* session manager already in Finished state */ ...)

    viewModel.events.test {
        viewModel.onAction(TrackingAction.Finish(snapshotFilePath = null))
        assertEquals(TrackingEvent.Saved, awaitItem())
    }
}
```

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

## What to test, and coverage priorities (current state: near-zero coverage)

Domain and data have some tests; ViewModels have none yet. When asked to raise
coverage without a more specific target, prioritize in this order:
1. `domain`: pure logic first — `CalorieCalculator`, speed/Haversine calculations,
   `TrackingSessionManager`'s state transitions (`UpdateTrackingStateUseCase`), use
   cases like `SaveActivityUseCase`.
2. `data`: repository implementations, especially anything with offline/fallback logic.
3. ViewModels: write these as part of the MVI migration (test-first, see above), not
   as a separate pass against the current pre-migration API — tests written against
   `onStartClicked()`-style methods will be thrown away.
4. Compose UI tests: after a screen's ViewModel and Action/Event shape are stable.

## Detekt / CI note

`./gradlew test` must show the same test count before and after any test-framework or
dependency change (e.g. removing Truth) — a silent drop to zero discovered tests is the
failure mode to watch for, not just a red/green result.
