---
name: tm-testing
description: Use whenever writing or reviewing tests anywhere in TrailMetrics — domain, data, ViewModel/MVI, or Compose UI tests, on Android or in commonTest/KMP code. Fixes the testing stack (JUnit4 for Android, kotlin.test for KMP and assertions, hand-written fakes; MockK and Turbine are not in the catalog and are not added; no Truth, no JUnit5) and testing patterns per layer. Not for the code under test itself — see tm-kmp-shared or tm-android for that.
---

# TrailMetrics testing

## Stack (fixed — do not introduce an alternative)

| Layer | Framework | Assertions | Mocking |
|---|---|---|---|
| `domain`, other commonTest/KMP | `kotlin.test` | `kotlin.test` (`assertEquals`, `assertTrue`, ...) | fakes, not mocks — MockK has no Kotlin/Native artifact |
| `data`, Android-framework code (Robolectric, Compose), Android ViewModels | JUnit4 | `kotlin.test` | hand-written fakes |
| `data` HTTP-level tests (commonTest) | `kotlin.test` | `kotlin.test` | Ktor `MockEngine` (`ktor-client-mock`) serving a canned response to the real repository |

### What's actually available today

MockK and Turbine are not in `gradle/libs.versions.toml`; do not add them (`CLAUDE.md`: the
testing stack is fixed). Hand-written fakes and `kotlin.test` cover every layer:

- Android ViewModel/MVI tests add `kotlinx-coroutines-test` to JUnit4 + `kotlin.test` +
  fakes; all three are catalog entries (`junit`, `kotlin-test`, `kotlinx-coroutines-test`).
- Flow assertions: see "Coroutines / Flow". Don't use Turbine's `.test { awaitItem() }`.
- The three feature modules' JVM test source sets have `testImplementation` lines for those
  entries plus `:androidApp:core-testing`; a new Android module's first test adds the same
  lines to its `build.gradle.kts` (not a new dependency).
- Compose UI tests run on the JVM under Robolectric inside `testDebugUnitTest` (no emulator,
  no `androidTest`) in all three feature modules. Their `build.gradle.kts` lists the catalog
  entries (`robolectric`, `androidx-compose-ui-test-*`) and sets
  `testOptions.unitTests.isIncludeAndroidResources = true` so tests can read string
  resources. See "Compose UI tests".
- Ktor `MockEngine` is a `data` commonTest dependency (Android host and iOS simulator).
  Build the real repository on `HttpClient(MockEngine { respond(...) })` with the same
  `ContentNegotiation`/`Json` setup as `networkModule` and JSON shaped like the DTO (see
  `DirectionsRepositoryImplTest`). Don't fake `HttpClient` or the repository.

No JUnit5 anywhere in this project (evaluated and rejected, see `docs/architecture`). No
AssertK. No Truth (removed from `data`, its only user; no `com.google.truth` import remains).

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

Android-only tests (ViewModels, repositories) use fakes too. The fakes in `domain/src/commonTest/.../fakes/` aren't visible to other modules.
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
transitions instead of stubbing return values.

The iOS UI tests' fakes are Kotlin and live in `shared-uitest` (package
`dev.roozbahani.trailmetrics.uitest`, `src/iosMain`), not in `TestSupport`. They are hand-written
like every other fake, count calls in `MutableStateFlow<Int>` counters incremented with `update`,
hold calls on a `CompletableDeferred` gate and use no delay and no clock. When you write or change
one, read `xcuitest.md` first. The XCUITest side is in "XCUITest" below.

## Testing MVI ViewModels

Write the test against `onAction()` and the resulting `state`/`event` stream — never
against the old per-action public methods once a screen has been migrated to MVI
(see `tm-android`). When migrating, the `onAction` test comes first ("First move").

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

## First move by kind of change

| Change | Do first |
|---|---|
| Bug fix | The red test above, before the fix. |
| Behavior change | Update the existing test to the new behavior and see it fail for that reason, then change the code. |
| Refactor, no behavior change | Run the covering tests green; with none, write a characterization test of today's behavior and see it pass, then refactor. |
| New use case, domain logic | `kotlin.test` in `domain` commonTest on fakes of the repository interfaces. |
| ViewModel (Android) | A test against `onAction` and `state`/`events` on `core-testing` fakes; when migrating, written against the target State/Action/Event shape first, so it specifies and locks the behavior. |
| Repository, HTTP call (`data`) | A commonTest on the real repository: Ktor `MockEngine` for HTTP, the Room repository suite for storage. |
| Room schema | The frozen fixture for the old version, then the `MIGRATION_M_N` case ("Migration cases"). |
| Swift ViewModel, iOS flow | An XCTest in the package's `Tests` on the real Kotlin class built on `TestSupport` fakes; a UI flow: XCUITest. |

## Compose UI tests

When you write or change a Compose UI test, read `compose-ui-tests.md` first: the robot example,
the real-ViewModel screen-test setup, the double-tap reasoning and the Maps shadow details.

- `ComposeTestRule`, JUnit4 (`@get:Rule`). Use the Robot pattern once a screen has 3+ UI test cases
  or several tests share setup/assertion sequences: one robot class per screen, every method returns
  `this` for chaining. Don't reach for it for a 1-2 assertion smoke test: plain
  `composeTestRule.setContent { ... }` + a couple of `onNodeWith...` calls is clearer there.
- Screen tests run the real ViewModel (`feature-history`'s `DetailsScreenTest`/`HistoryScreenTest`
  are the pattern to copy): `@RunWith(RobolectricTestRunner::class)`, `@Config(sdk = [35])` (add
  `qualifiers = "w411dp-h891dp"` when a `LazyColumn` must compose several rows) and
  `createAndroidComposeRule<ComponentActivity>()`, so strings come from
  `rule.activity.getString(...)` instead of being copied into the test.
- Test the `<X>Root`, not only the stateless `<X>Screen`, so event handling (navigation callback,
  snackbar) is covered. `@Before` sets the main dispatcher and starts Koin with the feature's UI
  module plus fakes from `core-testing`; `@After` calls `stopKoin()` and `resetMain()`. Navigation
  lives in `androidApp/app`, so assert on the Root's callback (count its calls).
- Hold a suspending call with the fake's gate (a `CompletableDeferred` the fake awaits). Act,
  assert nothing happened yet, `complete(Unit)`, `rule.waitForIdle()`, assert. No `Thread.sleep`,
  no real delays.
- Double tap: `performTouchInput { down(center); up(); down(center); up() }`, never
  `click(); click()` (the first tap's recomposition can remove the button, so the test passes with
  or without the guard). Check it once by removing the guard in the working tree: the test must
  fail on the doubled call.
- Maps: when the test needs no map callback, wrap the content in
  `CompositionLocalProvider(LocalInspectionMode provides true)`; the map's content is not tested and
  no production seam is needed. When the test must drive a map callback (`MapEffect`,
  `GoogleMap.snapshot { }`), render the map as `TrackingScreenSnapshotTest` does, with test sources
  only (its `ShadowMapView` must extend `ShadowViewGroup`). A test that renders no map and must see
  an uninitialized Maps SDK (`TrackingScreenTest`) calls `FakeGoogleMap.uninstallFactories()` first.
- Find nodes by visible text and content description first; a `testTag` is a production
  change, so only when nothing else identifies the node. A merged node (a clickable `Card`)
  matches every text inside it: assert a row with `hasText(a) and hasText(b) ...`.

## XCUITest

When you write or change an XCUITest, a `UiTestScenario` or a fake in `shared-uitest`, read
`xcuitest.md` first: the run command, the seam and probe in detail, the CI shard and timing details.

The iOS UI tests are `iosApp/TrailMetricsUITests` (XCTest, no other library); the plan and its
decisions D5 to D7 are in `docs/epics/ios-ui-tests.md`.

- **Run.** Scheme `TrailMetricsUITests` (⌘U in Xcode, or the `xcodebuild test` command in `tm-ios`,
  "Build configurations and schemes", piped through `../scripts/filter-xcode-log.sh`). With an empty
  Maps key the Route UI tests that need the map fail.
- **Seam.** A test starts its scenario with `XCUIApplication.launched(scenario:)` (`Support/`); the
  name must be the Kotlin `name` of a `UiTestScenario` entry (an unknown name stops the app). Normal
  Debug and Release builds contain no seam.
- **Probe.** The overlay's counters are read only on a refresh tap: read them through
  `UITestProbe.refreshedCounters()` and `releasedCounters()`.
- **Determinism (D5).**
  - one `launch` per test, with its scenario; no test depends on another or on simulator state;
  - wait with `waitForExistence(timeout: 10)`; no `sleep`, no fixed delay, in tests or fakes;
  - for an absence, wait for a positive signal first (a probe read, a screen change), then
    assert the element does not exist;
  - held calls are released only through `uitest.probe.release`;
  - `continueAfterFailure = false`; SwiftLint `--strict` applies, so no force unwraps;
  - check once in the working tree that the test fails when the guarded behavior breaks.
- **Shards.** CI runs the UI tests in one `ios-ui` job; plan a shard step when they exceed about
  10 tests (cap 3).
- **Flakes (D6).** No retries, no `-retry-tests-on-failure`, no `XCTSkip`: red is red, and a
  failure without a related change gets a `BOARD.md` record.
- **Identifiers (D7).** Find elements by their text first; a View gets an
  `accessibilityIdentifier` (`<screen>.<element>`, e.g. `details.deleteButton`) only where text
  cannot find it (image-only buttons, rows, a label that changes).
- **Helpers** live in `iosApp/TrailMetricsUITests/Support/`; later scenarios reuse them.
- **Project file.** The targets use synchronized folders, so a new file needs no project change.
  If Xcode or a run rewrites `project.pbxproj` or `Info.plist`, `git restore` them; never commit
  that rewrite (CI's Xcode is older than the local one).

## Migration cases (Room)

When you write a Room migration case or a frozen fixture, read `room-migration-tests.md` first: the
harness files and how a fixture is built from the schema file.

This section is the canonical statement of the migration test (step 5 of the schema procedure). The
schema change procedure around it is in `tm-kmp-shared`, "Changing the database schema (Room)". Each
case writes a database file at an old version with plain SQL, outside Room, opens it through the
app's builder pipeline and `appMigrations`, and reads every row back through the DAO.

For a migration from M to N:
- If version M has no fixture yet, add one: its `schemaStatements` are copied from
  `data/schemas/.../M.json`, its rows are `INSERT` statements in version M's stored form written as
  literal text (never produced by the current converters), and it goes into
  `frozenDatabaseVersions`. `FrozenDatabaseVersionsSchemaTest` (host only) fails when a fixture
  differs from its schema file. Rows cover every column: each `ActivityType` name, null and non-null
  optional columns, empty and non-empty coordinate lists. A fixture never changes once its version
  has shipped.
- Add one case whose name contains `MIGRATION_M_N` (the schema check's rule (c) looks for that
  text). It opens the fixture and asserts, with `assertEquals` on whole `ActivityEntity` lists,
  every field of every row at N, including the value the migration gives each new or changed
  column, and the stored `user_version` N.
- A test that only names `MIGRATION_M_N`, or asserts a row count without the rows' fields, does
  not satisfy the reviewer: the schema check accepts it, so the assertions are what prove the
  rows survive.

Check a new case once in the working tree: break the migration (for example add a `DELETE` of one
row) and see the case fail on both platforms on the row assertion, then restore.

## What to test, and coverage priorities (current state: measured, uneven)

The merged Kover report (see `tm-pr-workflow`, Tier 1) is the current measure; `core`, `shared`,
`androidApp/app` and `androidApp/core-ui` have no tests of their own. `domain`, `data` and the
feature modules have a `koverVerify` minimum, so adding untested code there can fail the gate.
When asked to raise coverage without a more specific target, prioritize in this order:
1. `domain`: pure logic first — `CalorieCalculator`, speed/Haversine calculations,
   `TrackingSessionManager`'s state transitions (`UpdateTrackingStateUseCase`), use
   cases like `SaveActivityUseCase`.
2. `data`: repository implementations, especially anything with offline/fallback logic.
3. ViewModels (all four are on MVI with `onAction` tests): new or changed behavior gets one.
4. Compose UI tests: after a screen's ViewModel and Action/Event shape are stable.

## Detekt / CI note

`./gradlew test` runs zero KMP tests; the gate runs `allTests test`. After any test-framework
or dependency change, compare test counts before and after with the method in `tm-pr-workflow`
("PR description", Tier 1 item): per module and per target, from the JUnit XML. A silent drop
to zero discovered tests in one task is the failure mode to watch for, not just a red/green
result.
