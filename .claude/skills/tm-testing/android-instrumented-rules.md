# Rules for `androidTest` (a flake is a failed rule)

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the sub-section "Rules for `androidTest` (a flake is a failed rule)". The rules are unchanged; they are still cited as `tm-testing`, "Rules for `androidTest`".

### Rules for `androidTest` (a flake is a failed rule)

- **Run.** `scripts/android-ui-tests.sh [--tests <class>]`: a dedicated AVD of its own (`TrailMetrics_UITest`,
  headless, its own port, `ANDROID_SERIAL` pinned). The developer's emulator (`Pixel_10` or any other) is
  never started, wiped or installed on; never run `connectedDebugAndroidTest` by hand against whatever device
  is attached.
- **Names** are camelCase, not backtick sentences (a name with a space does not dex below API 30; `minSdk` is 26).
  Other naming as elsewhere.
- **Find nodes by visible text** (`By.text`, `By.textContains`, `By.desc`). A `testTag` is a production
  change, only when nothing else identifies the node.
- **Waits are bounded polls**: `device.wait(Until..., WAIT_MS)` or `LiveSessionRule.eventually(message) { }`
  (a deadline and a failure message that names what never happened). No fixed sleep; the poll interval inside
  the bounded loop is the only one. For an absence, wait for a positive signal first (the Activity is on
  screen), then assert it. After `pressHome` wait for the Home package before the next step (`LiveSessionRule`
  does); a failure message that names a state is a lambda, built at the deadline.
- **Isolation.** One real tracking session per test, started and discarded by `LiveSessionRule`
  (`manager.discard()` in `after`), so no test leaves a live or stored session: the real graph is shared by
  every test of the process. A test never depends on another or on device state; a scenario that needs a
  process boundary is not an ordinary test (it belongs to a host-driven design of its own).
- **Permissions** are granted in the test (`uiAutomation.grantRuntimePermission`), not by the host.
- **Red first, once.** Check in the working tree that the test fails when the guarded behavior breaks (revert
  the fix or remove the guard) and write the red evidence in a commit message. A fix that spans modules is reverted
  across all of them (`MainActivity` and `TrackingService` for #301).
- **No retries**: no `@Ignore`, no `assumeTrue` to skip, no Orchestrator or Gradle retry. Red is red; a failure
  without a related change is logged in `CI_FLAKES.md` (`tm-pr-workflow`, "Flake log"): a run that fails and then
  passes is detected and counted by `scripts/ui-flake.sh` ("Local UI flakes").
