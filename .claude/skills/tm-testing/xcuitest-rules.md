# XCUITest: the rules

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the section "XCUITest". The rules are unchanged; they are still cited as `tm-testing`, "XCUITest".

## XCUITest

When you write or change an XCUITest, a `UiTestScenario` or a fake in `shared-uitest`, read
`xcuitest.md` first: the run command, the seam and probe in detail, where the UI tests run (not in CI) and their timing.

The iOS UI tests are `iosApp/TrailMetricsUITests` (XCTest, no other library); the plan and its
decisions D5 to D7 are in `docs/epics/ios-ui-tests.md`.

- **Run.** Scheme `TrailMetricsUITests` (⌘U in Xcode, or the `xcodebuild test` command in `tm-ios`,
  "Build configurations and schemes", piped through `../scripts/filter-xcode-log.sh`). With an empty
  Maps key the Route UI tests that need the map fail.
- **What the simulator cannot show.** Real GPS, a locked or screen-off device, the system suspending or terminating the app and the lock-screen rendering of a Live Activity are not reproduced by the simulator or by an XCUITest, so a change to them ends with a human check on a device (`tm-pr-workflow`, "Tier 2: what automated tests cannot show", full text in its `tier2.md`), with its steps and reason.
- **Seam.** A test starts its scenario with `XCUIApplication.launched(scenario:)` (`Support/`); the
  name must be the Kotlin `name` of a `UiTestScenario` entry (an unknown name stops the app). Normal
  Debug and Release builds contain no seam.
- **Probe.** The overlay's counters are read only on a refresh tap: read them through
  `UITestProbe.refreshedCounters()` and `releasedCounters()`.
- **Determinism (D5).**
  - one `launch` per test, with its scenario; no test depends on another or on simulator state;
    the one exception is `LaunchPerformanceTests`, which launches several times with no scenario to
    measure the launch: it runs on request (`docs/performance/ios-cold-start.md`), never in the gate or
    the full run on `main` (`scripts/ios-ui-tests.sh` skips it; owner decision of 2026-11-26);
  - wait with `waitForExistence(timeout: 10)`; no `sleep`, no fixed delay, in tests or fakes;
  - for an absence, wait for a positive signal first (a probe read, a screen change), then
    assert the element does not exist;
  - held calls are released only through `uitest.probe.release`;
  - `continueAfterFailure = false`; SwiftLint `--strict` applies, so no force unwraps;
  - check once in the working tree that the test fails when the guarded behavior breaks.
- **Shards.** None (owner decision of 2026-11-25): the gate and the full run on `main` run the UI tests in one
  `scripts/ios-ui-tests.sh` run on one pinned simulator, and the script has no shard step. Look again when a full
  run takes over about 10 minutes. Why, in `xcuitest.md`, "Shards and CI timing".
- **Flakes (D6).** No retries, no `-retry-tests-on-failure`, no `XCTSkip`: red is red, and a
  failure without a related change is logged in `CI_FLAKES.md` (`tm-pr-workflow`, "Flake log").
- **Identifiers (D7).** Find elements by their text first; a View gets an
  `accessibilityIdentifier` (`<screen>.<element>`, e.g. `details.deleteButton`) only where text
  cannot find it (image-only buttons, rows, a label that changes).
- **Helpers** live in `iosApp/TrailMetricsUITests/Support/`; later scenarios reuse them.
- **Project file.** The targets use synchronized folders, so a new file needs no project change.
  If Xcode or a run rewrites `project.pbxproj` or `Info.plist`, `git restore` them; never commit
  that rewrite (CI's Xcode is older than the local one).
