# CI flakes

One entry per flake signature (job, step, test, first error line). Rules: `tm-pr-workflow`,
"Flake log"; watching and re-running: `tm-agent-loop`, section 6.

Entry fields: Signature, Count, Status (`open` | `fixed`), Occurrences (date, run id, PR, whether
a re-run fixed it), Notes; `escalated: flake-<slug>` once the board record exists; for a fixed
entry the Fix (PR) and Learned (one line, the full entry is in `LEARNINGS.md`).

## ios-ui-route-map-press-lost

- Signature: job `iOS 3 — run UI tests (after 2a)` (formerly `iOS — run UI tests`), step `Run iOS UI tests`, tests `RouteGenerateTwiceUITests.test_generateTwice_requestsDirectionsOnce` and `RouteGenerateThenResetUITests.test_resetWhileGenerating_leavesACleanScreen`, first error line "Generate button not enabled after 3 waypoints" (since the helper change: "map press 1 of 3 did not add a waypoint: count 0, expected 1")
- Count: 3
- Status: open
- escalated: flake-ios-ui-route-map-press-lost
- Occurrences:
  - 2026-10-17, run 39049148407 (push to `main`, merge of #161), re-run: no
  - 2026-10-17, run 39074545852 (push to `main`), re-run: no
  - 2026-10-18, run 39137921296 (push to `main`, merge of #167), re-run: no
- Notes: moved from the board record `ios-ui-route-generate-twice-failed-on-main`; its investigation stays in `flake-ios-ui-route-map-press-lost`.

## ios-ui-details-launch-timeout

- Signature: job `iOS 3 — run UI tests (after 2a)`, step `Run iOS UI tests`, first Details test `DetailsDeleteTwiceUITests.test_deleteConfirmedTwice_deletesOnce`, first error line "Failed to launch" / "Timed out while launching application via Xcode" (73.5 s and 80.9 s) in `XCUIApplication+Scenario.swift`; in one run `DetailsFailedDeleteUITests` also failed to launch ("Failed to get background assertion for target app", 43.0 s)
- Count: 2
- Status: open
- Occurrences:
  - 2026-10-20, run 39425719146 (push to `main`, merge of #177), re-run: no
  - 2026-10-20, a pull request without iOS, data or test changes, run id not recorded (not in the last 200 `ci.yml` runs as a failure), re-run: unknown
- Notes: no test body ran and the Route tests passed. Runner image, Xcode and simulator matched seven green runs; the automation-session setup in the first test of green runs took 5.9 to 56.4 s against a limit of about 60 s. Reading: a launch stall on the runner, about 80% sure, not proven. The step now boots the simulator with `simctl bootstatus -b` and prefixes every `xcodebuild` line with a UTC time. No retry and no longer timeout (D6). Moved from the board record `ios-ui-launch-timeout-on-ci`.

## ios-ui-details-delete-button-not-found

- Signature: job `iOS 3 — run UI tests (after 2a)`, step `Run iOS UI tests`, test `DetailsDeleteTwiceUITests.test_deleteConfirmedTwice_deletesOnce`, first error line "XCTAssertTrue failed - Details delete button not found (first)" (`DetailsDeleteTwiceUITests.swift:49`, after the 10 s wait for `details.deleteButton`)
- Count: 1
- Status: open
- Occurrences:
  - 2026-10-22, run 39829868547 (PR #207, head 15873e8), re-run: yes (attempt 2 green)
- Notes: the test ran 121.4 s; the same test class also failed at launch on 2026-10-20 (`ios-ui-details-launch-timeout`), a different first error line, so a separate entry; a link between them is not shown.

## classify-changes-usage-error-fixture

- Signature: local gate step "change classification self-test", `scripts/classify-changes.sh --self-test`, fixture `usage-error`, first error line "missing: usage error" (22 of 23 fixtures passed)
- Count: 1
- Status: open
- Occurrences:
  - date and run id not recorded (a local gate run on the branch of #180 before any push), PR #180, re-run: yes (the next gate run passed)
- Notes: it passed on a clean `main`, and 30 consecutive reruns on the branch's clean tree did not reproduce it; the cause is unknown. Moved from the board record `classify-changes-self-test-failed-once`.
