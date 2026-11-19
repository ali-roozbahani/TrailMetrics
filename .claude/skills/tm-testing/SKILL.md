---
name: tm-testing
description: Use whenever writing or reviewing tests anywhere in TrailMetrics — domain, data, ViewModel/MVI, or Compose UI tests, on Android or in commonTest/KMP code. Fixes the testing stack (JUnit4 for Android, kotlin.test for KMP and assertions, hand-written fakes; MockK and Turbine are not in the catalog and are not added; no Truth, no JUnit5) and testing patterns per layer. Not for the code under test itself — see tm-kmp-shared or tm-android for that.
---

# TrailMetrics testing

## Topic files

Read each file when the task or the diff reaches its topic, not before; a reviewer reads it for a diff that touches the
topic. Section headings are unchanged, so a reference to `tm-testing`, "<heading>", is found in this file or in the file
named here.

| File | Read it when |
|---|---|
| `compose-ui-test-rules.md` ("Compose UI tests"), then `compose-ui-tests.md` | a Compose UI test is written or changed (`src/test` of a feature module with `createAndroidComposeRule`, a robot) |
| `android-instrumented-rules.md` ("Rules for `androidTest`") | a test under `androidApp/app/src/androidTest` is written or changed |
| `xcuitest-rules.md` ("XCUITest"; the rules D5 determinism, D6 flakes and D7 identifiers of the XCUITest section), then `xcuitest.md` | an XCUITest, a `UiTestScenario` or a fake in `shared-uitest` is written or changed |
| `room-migration-rules.md` ("Migration cases (Room)"), then `room-migration-tests.md` | a migration case, a frozen fixture or the migration harness is written or changed |


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
  resources. See "Compose UI tests" (`compose-ui-test-rules.md`).
- The one `androidTest` source set is in `androidApp/app` ("Which test goes where"); it adds
  `androidx.test.uiautomator` (catalog entry `androidx-test-uiautomator`) and the existing `kotlin-test`
  to that module only.
- Ktor `MockEngine` is a `data` commonTest dependency (Android host and iOS simulator).
  Build the real repository on `HttpClient(MockEngine { respond(...) })` with the same
  `ContentNegotiation`/`Json` setup as `networkModule` and JSON shaped like the DTO (see
  `DirectionsRepositoryImplTest`). Don't fake `HttpClient` or the repository.
- The Koin graph that `initKoin` builds is tested in `shared` (`KoinGraphAndroidTest` on the
  Android host, `KoinGraphIosTest` on the simulator, helper `checkKoinGraph` in commonTest): the real
  modules, every definition resolved, only the platform pieces that need a `Context` or a device
  overridden by fakes. A new binding is covered by it; a new binding that needs a `Context` or a
  device needs its fake in that test too. `koin-test`'s `checkModules` is deprecated and `verify` is
  JVM-only reflection, so neither is used.

No JUnit5 anywhere in this project (evaluated and rejected, see `docs/architecture`). No
AssertK. No Truth (removed from `data`, its only user; no `com.google.truth` import remains).

## Which test goes where

Every feature and every bug fix is proven by a test, never by a hand check. Pick the lowest tier that
can fail on the defect:

1. **`domain` / `data` (`kotlin.test`, commonTest)**: logic, state machines, repositories. The default for
   anything with no Android or UI framework.
2. **Android JVM tests (JUnit4 + Robolectric + fakes)**: ViewModels, Compose screens and Roots, a `Service`
   or `Activity` built by Robolectric, intents and the contents of a `PendingIntent`. The default for Android
   behavior; a feature or a fix starts here.
3. **Android instrumented tests (`androidApp/app/src/androidTest`, a real emulator)**: only when the defect or
   feature depends on something Robolectric does not run: the real notification shade and the system's
   handling of a `PendingIntent`, an Activity and task that the system creates, real window insets and input
   method, the foreground-service lifecycle, a process boundary. The PR says why ("not provable on the JVM
   because ..."). If a Robolectric test can fail on the defect, write that one, even when an instrumented one
   would also be possible.
4. **XCUITest**: the iOS counterpart of tier 3 ("XCUITest", `xcuitest-rules.md`).
5. **Human check** (Tier 2 of `tm-pr-workflow`): only what no tier can show (real GPS in the field, what the
   Maps SDK draws, a human judgement of design), with the reason in the PR.

A bug found by hand on a device is not a reason for a human check: write the test that reproduces it (red on
the unfixed code, "Bugfixes: red test first"), then fix. The UI tests of both platforms run in the local gate on
this machine, the full suite of each platform a branch touches (`scripts/classify-changes.sh --ui-scope`:
`androidApp/` Android, `iosApp/` and `shared-uitest/` iOS, `domain`, `data`, `core`, `shared` and the root Gradle
and catalog files both, docs, skills, tooling scripts and workflow files none); the gate prints the AVD, simulator, runtime and
Xcode versions it ran on. CI runs no UI tests, on either platform: they run in the gate and in the full run on `main`.

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
one, read `xcuitest.md` first. The XCUITest side is in "XCUITest" (`xcuitest-rules.md`).

## Testing MVI ViewModels

Write the test against `onAction()` and the resulting `state`/`event` stream — never
against the old per-action public methods once a screen has been migrated to MVI
(see `tm-android`). When migrating, the `onAction` test comes first ("First move").

```kotlin
@Test
fun `Pause action pauses an active tracking session`() = runTest(testScheduler) {
    // sessionManager: a real TrackingSessionManager built from fakes (see "Fakes over mocks")
    val viewModel = TrackingViewModel(sessionManager, fakeProfileRepo, TrackingMetricsUseCase(CalorieCalculator()), saveActivityUseCase, ActivityType.Running, emptyList(), fakeClock)
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
before or together with the fix. Put the red evidence in a commit message (the test commit, or the fix
commit when they are one): the test name and its failure message, as `tm-pr-review` item 4 checks it. A pinned "currently ..." test of a known defect is rewritten to assert the correct
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
| Room schema | The frozen fixture for the old version, then the `MIGRATION_M_N` case ("Migration cases", `room-migration-rules.md`). |
| Swift ViewModel, iOS flow | An XCTest in the package's `Tests` on the real Kotlin class built on `TestSupport` fakes; a UI flow: XCUITest. |

## What to test, and coverage priorities (current state: measured, uneven)

The merged Kover report (see `tm-pr-workflow`, Tier 1) is the current measure; `core`
and `androidApp/core-ui` have no tests of their own.
`domain`, `data`, `shared`, `androidApp/app` and the feature modules have a `koverVerify` minimum, so adding untested code there can fail the gate.
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
