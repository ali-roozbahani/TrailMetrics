# XCUITest and `shared-uitest`: run, seam, probe, CI

Read from `xcuitest-rules.md`, "XCUITest", and `SKILL.md`, "Fakes over mocks". The rules (determinism D5, flakes D6,
identifiers D7, the project file) are there; this file holds the procedures and the description of
the test seam. The plan and its decisions are in `docs/epics/ios-ui-tests.md`.

## Run

Scheme `TrailMetricsUITests`: in Xcode select it and press ⌘U; from the shell, from `iosApp/`, the
command in `tm-ios` ("Build configurations and schemes", `build-and-schemes.md`): `xcodebuild test -scheme
TrailMetricsUITests` with a concrete simulator id, `-skipMacroValidation`, the arm64 flags,
`CODE_SIGNING_ALLOWED=NO`, piped through `../scripts/filter-xcode-log.sh`. The app needs the
machine's Maps key configuration for the real map; with an empty key the Route tab shows a message
instead of the map (`RouteMapConfiguration.isMapAvailable`), so the Route UI tests that need the
map fail.

## Variant and seam

The scheme builds `Debug-UITest`, which links the test-only framework variant of `shared-uitest`
and sets `UITEST_SEAM`. Normal Debug and Release builds contain no seam.

A test starts its scenario with `XCUIApplication.launched(scenario:)` (`Support/`), which passes
`-uiTestScenario <name>` (the Kotlin `name` of a `UiTestScenario` entry). `TrailMetricsApp.init()`
then calls `doInitKoinIosForUiTest(scenario:)`; without the argument the app runs the normal
composition root, an unknown name stops it.

## Probe

In a scenario launch the app shows a top-centre overlay: text `uitest.probe` (`refreshes=<n>
directions=<n> directionsDone=<n> saves=<n> deletes=<n> waypoints=<n> warning=<0|1>`: the refresh generation,
the fakes' counters, the Route map's waypoint count, read by reflection from the map's delegate in
`UITestWaypointCount`, -1 if not found, and whether the unsaved-session warning is raised), and three buttons:

- `uitest.probe.refresh`: re-reads the counters and increments the generation.
- `uitest.probe.release`: completes every held call, leaves the text alone.
- `uitest.probe.addWaypoint`: adds the next of five fixed Route waypoints and returns at once.
  `UITestWaypointSeam` calls the map delegate's public `didLongPressAt` with a coordinate from the
  map's projection, so the coordinator and view model run as for a press and only the SDK's gesture
  recognition is skipped; the text stays as it is, a refresh reads the result.

The counters are read only on a refresh tap. `UITestProbe.refreshedCounters()` reads the generation,
taps refresh and returns the text only once its generation is higher, so a read is never older than
its tap (it may time out, never return a stale value; a second tap after 10 s covers a lost one);
`releasedCounters()` taps release, then does the same.

## Shards and CI timing

CI no longer runs the UI tests: the gate and the full run on `main` do, through `scripts/ios-ui-tests.sh`
(the pinned simulator `TrailMetrics_UITest`, iPhone 17, iOS 26.5). The script boots the simulator and
waits for it (`simctl bootstatus -b`) before `xcodebuild`, and prints its pins; the step's log is the
place to time a launch timeout.

No shard step (owner decision of 2026-11-25). CI runs no UI tests, and the gate and the full run on `main` run
them as one heavy run on one pinned simulator, about 250 s. Parallel simulators do not fit a 16 GB Mac and the
heavy-run lock (`scripts/heavy-run.sh`, one heavy run at a time), and shards run one after another would only add
the launch and boot overhead of each. The trigger to look again is a full run over about 10 minutes; then a
shard step would be a change of `scripts/ios-ui-tests.sh`.

## Fakes in `shared-uitest`

The iOS UI tests' fakes are Kotlin and live in `shared-uitest` (package
`dev.roozbahani.trailmetrics.uitest`, `src/iosMain`), not in `TestSupport`: the app reaches them only
through the test-only variant of the framework, which UI-test builds alone link (ADR-002,
"Amendment"). Their tests are `kotlin.test` in `shared-uitest/src/iosTest`, run by
`./gradlew :shared-uitest:iosSimulatorArm64Test` and by the gate's `allTests`; the module has no
Kover floor (iOS targets only, which Kover can't measure).
