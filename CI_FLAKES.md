# CI flakes

One entry per flake signature (job, step, test, first error line). Rules: `tm-pr-workflow`,
"Flake log"; watching and re-running: `tm-agent-loop`, section 6.

Entry fields: Signature, Count, Status (`open` | `fixed (unverified)` | `fixed`), Occurrences (date,
run id, PR, whether a re-run fixed it), Notes; `escalated: flake-<slug>` once the board record
exists; for a fixed entry the Fix (`#<PR number>`) and Learned (one line, the full entry is in
`LEARNINGS.md`). A PR that fixes a flake sets `fixed (unverified)`, the status of a board record
until its Done when is shown (5 consecutive green runs of the job on `main` after the fix's merge
commit); `fixed` only once they are. A failure with the signature of a `fixed (unverified)` or
`fixed` entry reopens it to `open` and adds the occurrence.

## ios-ui-route-map-press-lost

- Signature: job `iOS 3 — run UI tests (after 2a)` (formerly `iOS — run UI tests`), step `Run iOS UI
  tests`, tests `RouteGenerateTwiceUITests.test_generateTwice_requestsDirectionsOnce` and
  `RouteGenerateThenResetUITests.test_resetWhileGenerating_leavesACleanScreen`, first error line
  "Generate button not enabled after 3 waypoints" (since the helper change: "map press 1 of 3 did
  not add a waypoint: count 0, expected 1")
- Count: 3
- Status: open
- escalated: flake-ios-ui-route-map-press-lost
- Occurrences:
  - 2026-10-17, run 39049148407 (push to `main`, merge of #161), re-run: no
  - 2026-10-17, run 39074545852 (push to `main`), re-run: no
  - 2026-10-18, run 39137921296 (push to `main`, merge of #167), re-run: no
- Notes: moved from the board record `ios-ui-route-generate-twice-failed-on-main`; its investigation
  stays in `flake-ios-ui-route-map-press-lost`.

## ios-ui-details-launch-timeout

- Signature: job `iOS 3 — run UI tests (after 2a)`, step `Run iOS UI tests`, first Details test
  `DetailsDeleteTwiceUITests.test_deleteConfirmedTwice_deletesOnce`, first error line "Failed to
  launch" / "Timed out while launching application via Xcode" (73.5 s and 80.9 s) in
  `XCUIApplication+Scenario.swift`; in one run `DetailsFailedDeleteUITests` also failed to launch
  ("Failed to get background assertion for target app", 43.0 s)
- Count: 6
- Status: open
- escalated: flake-ios-ui-details-launch-timeout
- Occurrences:
  - 2026-10-20, run 39425719146 (push to `main`, merge of #177), re-run: no
  - 2026-10-24, run 40122507751 (push to `main`, merge of #219), re-run: no. Same signature:
    `DetailsDeleteTwiceUITests` "Failed to launch" (73.1 s), then `DetailsFailedDeleteUITests`
    "Failed to get background assertion for target app" (7.3 s). Later pushes to `main` ran green
    with the UI tests unchanged
  - 2026-10-20, a pull request without iOS, data or test changes, run id not recorded (not in the
    last 200 `ci.yml` runs as a failure), re-run: unknown
  - 2026-11-11, run 43035083679 (PR #254, head `2ecfefc`; scripts and CI wiring, no iOS change),
    re-run: yes, fixed it (attempt 2 green). Same signature: `DetailsDeleteTwiceUITests` "Failed
    to launch" (73.2 s), then `DetailsFailedDeleteUITests` "Failed to get background assertion
    for target app"
  - 2026-11-11, run 43059387065 (PR #256, head `0043a74`; scripts, CODEOWNERS and a skill line,
    no iOS change), re-run: yes, fixed it (attempt 2 green). Same signature:
    `DetailsDeleteTwiceUITests` "Failed to launch" (64.6 s); `DetailsFailedDeleteUITests` passed
  - 2026-11-12, run 43204374961 (PR #266, head `218ee91`; iOS package code, no UI-test change), re-run:
    yes, fixed it (attempt 2 green). Same signature: `DetailsDeleteTwiceUITests` "Failed to launch"
    (84.6 s), then `DetailsFailedDeleteUITests` "Failed to get background assertion for target app"
- Notes: no test body ran and the Route tests passed. Runner image, Xcode and simulator matched
  seven green runs; the automation-session setup in the first test of green runs took 5.9 to 56.4 s
  against a limit of about 60 s. Reading: a launch stall on the runner, about 80% sure, not proven.
  The step now boots the simulator with `simctl bootstatus -b` and prefixes every `xcodebuild` line
  with a UTC time. No retry and no longer timeout (D6). Moved from the board record
  `ios-ui-launch-timeout-on-ci`.

## ios-ui-details-delete-button-not-found

- Signature: job `iOS 3 — run UI tests (after 2a)`, step `Run iOS UI tests`, test
  `DetailsDeleteTwiceUITests.test_deleteConfirmedTwice_deletesOnce`, first error line "XCTAssertTrue
  failed - Details delete button not found (first)" (`DetailsDeleteTwiceUITests.swift`, after the 10
  s wait for `details.deleteButton`)
- Count: 1
- Status: open
- Occurrences:
  - 2026-10-22, run 39829868547 (PR #207, head 15873e8), re-run: yes (attempt 2 green)
- Notes: the test ran 121.4 s; the same test class also failed at launch on 2026-10-20
  (`ios-ui-details-launch-timeout`), a different first error line, so a separate entry; a link
  between them is not shown.

## classify-changes-usage-error-fixture

- Signature: local gate step "change classification self-test", `scripts/classify-changes.sh
  --self-test`, fixture `usage-error`, first error line "missing: usage error" (22 of 23 fixtures
  passed)
- Count: 1
- Status: open
- Occurrences:
  - date and run id not recorded (a local gate run on the branch of #180 before any push), PR #180,
    re-run: yes (the next gate run passed)
- Notes: it passed on a clean `main`, and 30 consecutive reruns on the branch's clean tree did not
  reproduce it; the cause is unknown. Moved from the board record
  `classify-changes-self-test-failed-once`.

## ios-ui-details-failed-delete-row-not-found

- Signature: job `iOS 3 — run UI tests (after 2a)`, step `Run iOS UI tests`, test
  `DetailsFailedDeleteUITests.test_failedDelete_showsErrorAndKeepsDetails`, first error line
  "XCTAssertTrue failed - Seeded activity row not found" (`DetailsFailedDeleteUITests.swift:26`,
  after 82.6 s)
- Count: 1
- Status: open
- Occurrences:
  - 2026-10-22, run 39767445121 (push to `main`, head 39b6f40), re-run: no
- Notes: the same test passed in run 39425719146 (22.9 s) and in the pushes after this one (for
  example 74ef637); `iosApp/TrailMetricsUITests` and `iosApp/Packages/History` did not change
  between 39b6f40 and 74ef637. The 82.6 s is the launch stall of `ios-ui-details-launch-timeout`
  or a slow first screen; not shown which.

## ios-tracking-finish-failed-save-wait

- Signature: job `iOS 2b — lint, app build, package tests`, step `Run iOS package tests`, test
  `TrackingViewModelFinishTests.test_onFinishClicked_afterFailedSave_savesAgain`, first error line
  "failed - Condition not met within 2.0 seconds" (`TrackingViewModelFinishTests.swift:43`)
- Count: 1
- Status: fixed (unverified)
- Fix: #264 (default `waitUntil` timeout 10 s)
- Learned: a fixed 2 s default bound in a shared wait helper fails on a loaded runner; see `LEARNINGS.md`, "Swift test wait helper: a 2 s default bound failed three times on CI".
- Occurrences:
  - 2026-10-20, run 39459833673 (push to `main`, head fe41afd), re-run: no
- Notes: the test took 16.1 s on this run. `iosApp/Packages/Tracking` did not change between
  fe41afd and efc4e7f, and run 39497155083 (efc4e7f) was green. The wait in the test is a fixed 2.0 s
  on a loaded runner; the test was rewritten by #209 since, so the line may be gone.

## android-package-debug-incremental-failure

- Signature: job `Android — Lint, Detekt, Tests, Build`, step `Build`, task
  `:androidApp:app:packageDebug`, first error line "A failure occurred while executing
  com.android.build.gradle.tasks.PackageAndroidArtifact$IncrementalSplitterRunnable" (24 s, no cause
  line in the log)
- Count: 2
- Status: open
- Occurrences:
  - 2026-10-21, run 39606497367 (push to `main`, head 90a0f7d), re-run: no
  - 2026-11-10, run 42835745551 (push to `main`, merge of #246, head 79fb11b), re-run: no
- Notes: class infra (runner or restored Gradle cache), not shown. `androidApp` and the Gradle files
  did not change between 90a0f7d and 184beba, and run 39598565016 (184beba) was green.
  Occurrence 2: the build failed in 15 s with the same first error line and no cause line in the log.
  #246 changed no `androidApp/app` file (only `androidApp/feature-tracking`, a skill doc and
  `BOARD.md`), and the previous run on `main` (42828048444, #245) was green.

## ios-route-pending-events-wait

- Signature: job `iOS 2b — lint, app build, package tests`, step `Run iOS package tests`, test
  `RouteViewModelPendingEventsTests.test_eventAfterConsumerCancelled_isDeliveredOnceToNextStreamOnly`,
  first error line "failed - Condition not met within 2.0 seconds" (`RouteViewModelPendingEventsTests.swift`,
  the last `waitUntil` of the test; two assertion failures follow from it)
- Count: 1
- Status: fixed (unverified)
- Fix: #264 (default `waitUntil` timeout 10 s)
- Learned: same cause and fix as `ios-tracking-finish-failed-save-wait`; see `LEARNINGS.md`, "Swift test wait helper: a 2 s default bound failed three times on CI".
- Occurrences:
  - 2026-11-10, run 42813382887 (push to `main`, merge of #240), re-run: no
- Notes: the test ran 29.9 s; the other 42 Route tests and the History and Tracking packages passed in
  the same run. The Swift sources are those of run 42812119886 (#239, green): the diff from 43be50a to
  267e720 is `BOARD.md` only. Cause class: the wait is `waitUntil`'s default fixed 2.0 s bound on a loaded
  runner, with the same first error line and cause as `ios-tracking-finish-failed-save-wait` (another test
  and package) and the former board record of the Tracking Finish test (deleted by the fix), which named only that test. Why the runner was slow is not shown.

## ios-route-draft-read-wait

- Signature: job `iOS 2b — lint, app build, package tests`, step `Run iOS package tests`, test
  `RouteViewModelDraftTests.test_failingRead_startsEmptyPlanWithoutErrorAndKeepsStoredRow`, first
  error line "failed - Condition not met within 2.0 seconds"
- Count: 2
- Status: open
- Occurrences:
  - 2026-11-12, run 43123250071 (push to `main`, merge of #262), re-run: no. The test took 14.3 s.
    "Condition not met within 2.0 seconds"
  - 2026-11-12, run 43204374961 (PR #266, head `218ee91`; no Route change), re-run: yes, fixed it
    (attempt 2 green). After #264 (default `waitUntil` timeout 10 s): "Condition not met within 10.0
    seconds" at `RouteViewModelDraftTests.swift`, the test took 33.1 s
- Notes: the merge of #262 changed scripts and skills, no Swift source; the same fixed 2.0 s default
  bound as `ios-route-pending-events-wait` and `ios-tracking-finish-failed-save-wait`.
  Reopened by the second occurrence: #264 set it to `fixed`, and the 10 s bound did not hold. The
  runner stalled for more than 10 s inside this test, so the bound alone is not the cause; the wait
  it fails on is not shown. `ios-tracking-finish-failed-save-wait` and `ios-route-pending-events-wait`
  stay `fixed` until they fail again.

## ios-2a-job-not-acquired

One entry for the class "a macOS job is not acquired by a runner" (the slug names the first job it was seen on); the count is per
run, and the jobs it hit are counted below.

- Signature: job `iOS 2a — build UI-test app`, `iOS 2b — lint, app build, package tests` or `iOS 3 — run UI tests (after 2a)`, no
  step ran (the job has no steps), first error line "The job was not acquired by Runner of type hosted even after multiple attempts"
  (check-run annotation; with "Due to capacity constraints, jobs targeting macOS arm64 runners may experience longer queue
  times."). `iOS — all stages` then failed, and a job that needs the lost one was skipped or abandoned
- Count: 3 (runs). By job: `iOS 2a` 2, `iOS 2b` 1, `iOS 3` 1
- Status: open
- escalated: flake-ios-2a-job-not-acquired
- Occurrences:
  - 2026-11-12, run 43287492527 (push to `main`, merge of #270), job `iOS 2a`, re-run: no (a run on `main` is
    never re-run). The job waited 15 minutes (19:11:00 to 19:26:01) with no runner and was
    cancelled by GitHub; `iOS — all stages` failed with "ios-build-ui result is abandoned" and `iOS 3` was skipped
  - 2026-11-13, run 43459951394 (push to `main`, merge of #281), job `iOS 3`, re-run: no. The job waited 15 minutes (16:14:54
    to 16:29:55) and was cancelled; `iOS 2a` and `iOS 2b` of the run passed (so the app and the UI-test products were built)
  - 2026-11-13, run 43461639786 (push to `main`, merge of #282), jobs `iOS 2a` and `iOS 2b`, re-run: no. Both waited 15 minutes
    (16:20:01 to 16:35:02) and were cancelled; `iOS 3` was skipped
- Notes: class infra (macOS runner capacity), not the diff: in each run the other jobs passed (Android and tooling, and in the first
  run `iOS 2b`, which builds the app on the same runner label), and the changes were a UI test (#270, which that run never built or
  ran), scripts and lists (#281) and Markdown (#282). All three are pushes to `main`, which are never re-run. The owner's note: if
  it keeps recurring we revisit pinning the macOS label (not changed now; a workflow change only the owner can push).

## ios-ui-probe-refresh-timeout

- Signature: job `iOS 3 — run UI tests (after 2a)`, step `Run iOS UI tests`, tests
  `RouteGenerateThenResetUITests.test_resetWhileGenerating_leavesACleanScreen`,
  `RouteGenerateTwiceUITests.test_generateTwice_requestsDirectionsOnce`,
  `RouteMapLongPressUITests.test_longPress_addsAWaypoint` and
  `TrackingFinishTwiceUITests.test_finishTwice_savesOneActivity`, first error line "failed - Probe
  did not refresh within 10 s (still not read yet: tap Refresh)" (`UITestProbe.swift`)
- Count: 1
- Status: open
- Occurrences:
  - 2026-11-12, run 43213470138 (PR #267, head `f5d0d3b`; a new UI test and a scenario in
    `shared-uitest`), re-run: yes, fixed it (attempt 2 green). The four tests failed one after the
    other after 128.7, 49.1, 42.8 and 34.8 s; the four tests before them (Details, Launch and the
    new `RestoredSessionOfferUITests`) passed
- Notes: every test that reads the probe after the first failure failed the same way, so the
  runner or simulator was probably stuck, not four tests. The same eight tests passed in one local
  run on the same head. The signature differs from `ios-ui-route-map-press-lost` (a map press) and
  `ios-ui-details-launch-timeout` (a launch).


## ios-ui-details-failed-delete-error-alert-not-shown

- Signature: job `iOS 3 — run UI tests (after 2a)`, step `Run iOS UI tests`, test
  `DetailsFailedDeleteUITests.test_failedDelete_showsErrorAndKeepsDetails`, first error line
  "XCTAssertTrue failed - Error alert not shown" (the assertion on the error alert in
  `DetailsFailedDeleteUITests.swift`, after 87.1 s)
- Count: 2
- Status: open
- Occurrences:
  - 2026-11-12, run 43318989709 (PR #273, head `9922b1a`; a change to `scripts/queue/queue.sh` and
    `queue.md` only), re-run: yes, fixed it (attempt 2 green). The test before it
    (`DetailsDeleteTwiceUITests`, 43.2 s) and the seven after it passed
  - 2026-11-13, run 43431312123 (push to `main`, the merge of #280, head `c318851`; a change to scripts and skills only), re-run:
    no (the owner acknowledged the red run and classified it as this entry). The test took 84.0 s; the other eight tests passed;
    the stall was 18 s plus 33 s of "Wait for <app> to idle" around the tap on Delete
- Notes: the test took 87.1 s; the same test class passed in the re-run and in the later runs of #274 and
  #272. Not shown whether the alert never appeared or the run was slow: the signature differs from
  `ios-ui-details-failed-delete-row-not-found` (the seeded row assertion) and from the launch stalls of
  `ios-ui-details-launch-timeout`, which fail before a test body runs.
  Cause class `ui-test-idle-stall`, trigger unknown (board: ui-test-app-idle-stalls): three failures on two signatures (this one twice, `ios-ui-restored-session-offer-not-offered` once) took 87.1, 84.0 and 84.1 s on different tests, and each holds one long stall inside XCTest's own "Wait for <app> to idle" step before the test's last 10 s wait: 49 s, 18 s plus 33 s, and exactly 60.0 s. Every wait in the UI tests is 10 s and the CI step sets no per-test allowance (the gate's 90 s is not set in ci.yml), so no wait or timeout of about 80 s explains it; the 60.0 s looks like XCTest's own app-idle wait giving up. What keeps the app busy is not shown. No retry and no longer wait was added.

## ios-ui-restored-session-offer-not-offered

- Signature: job `iOS 3 — run UI tests (after 2a)`, step `Run iOS UI tests`, test
  `RestoredSessionOfferUITests.test_storedPausedSession_isOfferedAtLaunchAsTheTrackingScreen`, first error line "XCTAssertTrue
  failed - The restored session was not offered: no Resume" (`RestoredSessionOfferUITests.swift`, after the 10 s wait for the
  Resume button, 84.1 s into the test)
- Count: 1
- Status: open
- Occurrences:
  - 2026-11-13, run 43451417675 (PR #281, head `e2c725f`; a change to the self-test lists, the classifier and its fixtures),
    re-run: yes, fixed it (attempt 2 green). The other eight tests passed; the stall was exactly 60.0 s of "Wait for <app> to
    idle" at the start of the test (after 4.3 s)
- Notes: the test passed in the same run's attempt 2 and in earlier runs (about 9 to 10 s).
  Cause class `ui-test-idle-stall`, trigger unknown: the stall here was exactly 60.0 s inside XCTest's "Wait for <app> to
  idle" step at the start of the test, before its last 10 s wait. The measurements of all three failures, why no wait or
  timeout of about 80 s explains them, and what is not shown are in the Notes of
  `ios-ui-details-failed-delete-error-alert-not-shown` (that signature occurred twice, this one once) and the board record
  `ui-test-app-idle-stalls`.
