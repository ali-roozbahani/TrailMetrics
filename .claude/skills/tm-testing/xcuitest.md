# XCUITest and `shared-uitest`: run, seam, probe, CI

Read from `SKILL.md`, "XCUITest" and "Fakes over mocks". The rules (determinism D5, flakes D6,
identifiers D7, the project file) are there; this file holds the procedures and the description of
the test seam. The plan and its decisions are in `docs/epics/ios-ui-tests.md`.

## Run

Scheme `TrailMetricsUITests`: in Xcode select it and press ⌘U; from the shell, from `iosApp/`, the
command in `tm-ios` ("Build configurations and schemes"): `xcodebuild test -scheme
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
directions=<n> directionsDone=<n> saves=<n> deletes=<n> waypoints=<n>`: the refresh generation, the
fakes' counters and the Route map's waypoint count, read by reflection from the map's delegate in
`UITestWaypointCount`, -1 if not found), and three buttons:

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

CI runs the UI tests in one `ios-ui` job. The "Run iOS UI tests" step boots the simulator and waits
for it (`simctl bootstatus -b`) before `xcodebuild`, and prefixes every `xcodebuild` output line with
a UTC time, plus `[ui-timing]` lines for boot ready and `xcodebuild` start: a launch timeout in a red
run is placed with those times (runner start, test start, app launch).

## Fakes in `shared-uitest`

The iOS UI tests' fakes are Kotlin and live in `shared-uitest` (package
`dev.roozbahani.trailmetrics.uitest`, `src/iosMain`), not in `TestSupport`: the app reaches them only
through the test-only variant of the framework, which UI-test builds alone link (ADR-002,
"Amendment"). Their tests are `kotlin.test` in `shared-uitest/src/iosTest`, run by
`./gradlew :shared-uitest:iosSimulatorArm64Test` and by the gate's `allTests`; the module has no
Kover floor (iOS targets only, which Kover can't measure).
