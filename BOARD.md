# Board

The backlog of what the agent does not do on its own: open epics, and tasks and drift that need
an owner decision or design, are over the PR queue's limit of 5, or come
from an owner-opened sweep. Follow-ups the agent can do are PRs of the local queue, not records
(`tm-pr-workflow`, "Board", rule 1). It is not a plan or a status tracker: if a record exists, the
item is open. Records are only added,
deleted, narrowed when partly done, or given a new Order to make room for an insertion. They
never move between sections.

Sections are by type: **Epics** (multi-PR, plan under `docs/epics/`), **Tasks** (one PR),
**Drift** (docs/skills/comments that disagree with the code, found but not fixed). Each
record is a `### <slug>` heading (kebab-case, unique, descriptive, never a counter) followed by
these fields, in order: Type (epic | task | drift), Area, Order, After (optional), Source,
Problem, Done when, Refs.

- **Order** is an integer, unique across the whole file. Ascending Order is the execution
  order across all three sections (lowest first). New values use gaps of 10 so a record can
  be inserted between two others. Within each section, records are sorted by Order.
- **After** lists the slugs (comma-separated) that must be gone from the board before this
  record may start. Each must exist, have a lower Order, and not form a cycle.
- Order does not replace planning: an epic still needs a human-approved plan under
  `docs/epics/` before any work starts.

`scripts/check-board.sh` checks this format (it runs first in `scripts/pre-push-check.sh` and
in CI); `scripts/check-board.sh --next` prints the record to take next. Rules for adding and
deleting records: the "Board" section of `.claude/skills/tm-pr-workflow/SKILL.md`.

## Epics

### ios-release-readiness
- Type: epic
- Area: iosApp, shared, docs
- Order: 65
- Source: owner decision 2026-11-16 (iOS skills spike follow-up)
- Problem: The iOS app has never been prepared for a distributed build. Open items, each a decision or a part of the work: (1) a privacy manifest for the app, the widget extension, and a decision for the KMP framework (fetch Apple's current rules when the work starts; do not store them in the repo); (2) the Release build links the debug XCFramework (`release-build-links-debug-xcframework`); (3) the Always location request is removed (owner decision 2: when-in-use plus the background location mode; queue PR `ios-always-location-removal`); (4) signing, archive and TestFlight; (5) a version and build number policy; (6) the inputs for the privacy policy and the App Privacy label (Firebase Crashlytics, owner decision 2026-11-25, adds: Diagnostics > Crash Data and > Other Diagnostic Data, not linked to the user, not used for tracking, purpose App Functionality, as Crashlytics' own privacy manifest declares them; Firebase Installations and GoogleDataTransport declare Other Diagnostic Data for Analytics in theirs; no advertising ID, no location in reports); (7) review notes for background location and the Live Activity; (8) the restricted Directions keys (`ios-release-readiness-restricted-directions-keys`). Reason for a record: an epic, with owner-level parts (the Apple account, signing, App Store Connect).
- Done when: A human-approved plan exists under `docs/epics/` that splits the agent's code and doc parts (1, 2, 3, 5, 6, 7 as text) from the owner's Apple account parts (4, plus the policy and label entries in App Store Connect), and every item above is done or declined with a reason.
- Refs: `iosApp/TrailMetrics/Info.plist`; `iosApp/TrackingWidget/`; `data/src/iosMain/kotlin/dev/roozbahani/trailmetrics/data/location/IosLocationRepositoryImpl.kt`; `release-build-links-debug-xcframework`; `epic-orchestration` skill.

### figma-design-system
- Type: epic
- Area: design
- Order: 900
- Source: chat 2026-10-01
- Problem: There is no design system and there are no screens in Figma. The goal is tokens and screens in Figma that agents read through the Figma MCP to implement UI. This is deliberately the LAST item on the board: start it only after everything else.
- Done when: a token-based design system and the main screens exist in Figma, and an agent can implement a screen from them on both platforms.
- Refs: `androidApp/core-ui`, `iosApp/Packages/DesignSystem`; Figma MCP.

## Tasks

### detekt-typed-rules-after-kotlin-2-4-support
- Type: task
- Area: config, scripts
- Order: 54
- Source: PR for no-println-text-check (owner request, 2026-11-18)
- Problem: detekt 1.23.8 embeds Kotlin 2.0.21 and cannot read the metadata of Kotlin 2.4 libraries, so a call of a Kotlin-declared function (`println`, `delay`, `runCatching`) stays unresolved in the typed run (`config/detekt/detekt.yml`, `LEARNINGS.md`). Four rules are off or do not fire for that reason: `RedundantSuspendModifier` (2 false hits on `main` at the time), `SuspendFunSwallowedCancellation` (did not report a planted `runCatching { delay(1) }`), `UnsafeCast` (the compiler rejects the same casts first, so this one may stay moot) and `ForbiddenMethodCall` for `println`/`print`, which `scripts/check-no-println.sh` covers as text meanwhile. Reason for a record: it waits for a detekt release the owner chooses to move to (a dependency change, not an agent follow-up).
- Done when: detekt is upgraded to a release that resolves Kotlin 2.4 library calls; `RedundantSuspendModifier`, `SuspendFunSwallowedCancellation`, `UnsafeCast` and `ForbiddenMethodCall` for `println`/`print` are measured again on a planted case each and enabled where they fire (the reason lines in `config/detekt/detekt.yml` and the `tm-robustness` "Mechanical rules" list updated to match); `scripts/check-no-println.sh`, its gate and CI steps, self-test, index line and CODEOWNERS lines are removed if `ForbiddenMethodCall` replaces it.
- Refs: `config/detekt/detekt.yml`; `build.gradle.kts` (`detektTyped`); `scripts/check-no-println.sh`; `tm-robustness` ("Mechanical rules"); `LEARNINGS.md` ("Typed detekt: a Kotlin 2.4 library call is unresolved").

### session-ended-by-itself-notification
- Type: task
- Area: domain, androidApp, iosApp
- Order: 62
- Source: owner decision 2026-11-19 (answer to Question 5 of the route-completion epic's plan under `docs/epics/`)
- Problem: After the route-completion epic, `TrackingSessionManager` ends a session by itself at the end of the planned route, also with the phone locked and the screen off. The user can then return to a finished session with no sign of when or why it ended: the Android foreground notification only disappears and the iOS Live Activity only ends. The owner decided (2026-11-19) that the user gets a notification when a session ends by itself at the route's end. Reason for a record: it needs a design the owner reviews, and it starts only after the epic is merged into `main`: a permission text on iOS (a notification permission with its purpose string), a channel on Android (the notification permission, which `tm-robustness` lists as asked on every entry today), what tapping the notification opens (the finished session's Finish card), the wording (the String Catalog on iOS, `strings.xml` on Android), and one domain event that both platforms use (the manager is the single place where the session ends by itself; `locationIssues` is the existing example of a one-shot flow from it, with the delivery caveat of `tm-kmp-shared`, "Events that must not be silently dropped").
- Done when: the owner has approved a short design (the permission texts, the Android channel, the tap target, the event); `domain` emits one event when the manager ends a session by itself (and not on Stop, which discards), with `kotlin.test` coverage; each platform shows the notification from it, with an adapter test and a test that the notification is not shown when the user ended the session; the human check (a locked device on each platform, the notification appears and opens the finished session) is done; the permission text is in the iOS privacy and App Privacy answers of `ios-release-readiness`; and this record is deleted.
- Refs: the route-completion epic's plan under `docs/epics/` (decision 5); `domain` `TrackingSessionManager`; `androidApp/feature-tracking` (the foreground service); `iosApp/Packages/Tracking` (`TrackingLiveActivityController`); `ios-release-readiness`; `tm-kmp-shared` ("Events that must not be silently dropped").

### ios-release-readiness-restricted-directions-keys
- Type: task
- Area: iosApp, androidApp, config
- Order: 66
- Source: owner decision 2026-11-16 (iOS skills spike follow-up)
- Problem: Part of the epic `ios-release-readiness`. Before the first distributed build (TestFlight or any build outside the owner's devices), the owner creates two restricted keys, one per platform, and the app switches to them. Owner decision: the current key is unrestricted and shared by both platforms, which is accepted for debug builds; it is not checked or changed here. Reason for a record: an owner action in the key provider's console, and a decision on how the app receives the new keys.
- Done when: Two restricted keys exist, one per platform, the app of each platform reads its own, and no key value is in the repository.
- Refs: `ios-release-readiness`; `config/`; `iosApp/` and `androidApp/` secrets configuration (git-ignored, never read or written by the agent).

### ios-session-store-file-protection-class
- Type: task
- Area: data, iosApp
- Order: 67
- Source: owner decision 2026-11-16 (iOS skills spike follow-up)
- Problem: The stored tracking session (the file or database that holds the session, with its plan) has no chosen iOS file protection class. It must be readable and writable while the device is locked, because tracking runs with the screen off, so a class that locks the file after the first unlock window or at lock would lose saves. Reason for a record: a decision on the class, with a device check (a locked device), which no test shows.
- Done when: The class of the session store is decided and set, written in the code's comment or docs, and a device check with the device locked, steps in the PR, shows saves work while locked and after a restart.
- Refs: `data/src/commonMain/kotlin/dev/roozbahani/trailmetrics/data/local/`; `data/src/iosMain`; `tm-kmp-shared` ('Changing the database schema (Room)' for the protected paths).

### data-networking-timeouts-retry-offline
- Type: task
- Area: data
- Order: 68
- Source: owner decision 2026-11-16 (iOS skills spike follow-up)
- Problem: The Directions call in `data` has no recorded decision on timeouts, retries and what the user sees offline. Reason for a record: the values and the offline behavior are a product and design decision.
- Done when: The Ktor client's request, connect and socket timeouts, the retry policy (which failures, how many) and the offline behavior are decided, set in `data`, tested with `MockEngine`, and mapped to `RouteError` cases shown on both platforms.
- Refs: `data/src/commonMain` (`networkModule`, `DirectionsRepositoryImpl`); `RouteError`/`RouteUiError` in `core`; `tm-kmp-shared`.

### ios-privacy-manifest-first-upload-check
- Type: task
- Area: iosApp
- Order: 69
- Source: owner decision 2026-11-16 (open human checks of PR #322 and #325)
- Problem: Part of the epic `ios-release-readiness`. The privacy manifests of PR #322 (app and widget; the Maps SDK ships its own, the KMP framework has none and is covered by the app's) cannot be checked by any test and were written from secondary sources, because Apple's own page did not load. Reason for a record: an owner decision of 2026-11-16 to track this check here; it needs the owner's Apple account, at the first TestFlight upload, and the owner decides when it is done.
- Done when: At the first TestFlight upload the owner (1) reads App Store Connect's processing email for missing declarations (ITMS-91053 and similar), (2) checks the reason codes `CA92.1` (user defaults) and `C617.1` (file timestamps) against Apple's own list of required-reason API categories, and (3) checks that precise location declared as collected, not linked and not for tracking, matches the App Privacy label answers; the manifests are corrected if any of the three differs, and this record is deleted.
- Refs: `iosApp/TrailMetrics/PrivacyInfo.xcprivacy`; `iosApp/TrackingWidget/PrivacyInfo.xcprivacy`; `ios-release-readiness`; `tm-ios` ("Architecture", privacy manifests).

### ios-crash-reporting-and-symbolication
- Type: task
- Area: iosApp, release (Firebase console, a signed build)
- Order: 70
- Source: spike kotlin-agent-skills 2026-11-17; owner decision 2026-11-25 (Firebase Crashlytics, free plan, no Analytics)
- Problem: Needs the owner's Firebase project, a signed build and the Crashlytics console; the agent has none of them. Part of the epic `ios-release-readiness`. The app reports crashes with Firebase Crashlytics from a Release build when `iosApp/TrailMetrics/GoogleService-Info.plist` (git-ignored) is in the app (a Debug build reports only with the launch argument `-crashReportingInDebug`, owner decision 2026-11-25); an uncaught Kotlin exception goes through the Kotlin hook `installFatalKotlinExceptionReporter`, which records its Kotlin stack with `record(exceptionModel:)` before the process aborts, and a Release build uploads its dSYM, which holds the Kotlin debug info. Checked on an unsigned Release simulator build (2026-11-25): the hook runs, the dSYM names the Kotlin functions with their Kotlin source files, the upload passes validation and the next launch sends to Crashlytics; whether the console shows the Kotlin frames symbolicated no test can show.
- Done when: the owner has run a signed Release build with the plist in place, with a local, uncommitted Kotlin crash (a top-level Kotlin function in `shared/src/iosMain` that throws `IllegalStateException`, called from `TrailMetricsApp.init` when the launch argument `-crashReportingCheck` is set; the agent also left it as `~/agent-workspace/keep-crashlytics-ios-kotlin-crash-check.patch`), reopened the app, and seen in the Crashlytics console the crash (SIGABRT in `Kotlin_terminateWithUnhandledException`) and the Kotlin exception event with its Kotlin frames symbolicated (the throwing function's name and Kotlin file); the App Privacy answers of `ios-release-readiness` include the Crashlytics rows.
- Refs: `ios-release-readiness`; `release-build-links-debug-xcframework`; `android-crash-and-anr-reporting`; `shared/src/iosMain/kotlin/dev/roozbahani/trailmetrics/shared/crash/FatalKotlinExceptionReporting.kt`; `iosApp/TrailMetrics/CrashReporting/CrashReporting.swift`; `tm-kmp-shared` ("`@Throws` policy"); `tm-robustness` (C4).

### ios-generated-string-catalog-symbols-experiment
- Type: task
- Area: iosApp
- Order: 71
- Source: owner decision 2026-11-16 (iOS skills spike follow-up)
- Problem: Xcode can generate Swift symbols for String Catalog keys. Whether that works inside the six SPM packages (the bundle is the package's) and replaces the `String(localized:bundle:)` and `Text(..., bundle: .module)` forms is not known. Reason for a record: an experiment whose result changes a rule in `tm-ios` ('Strings', `strings-and-accessibility.md`), so the owner decides what to adopt.
- Done when: One compile check in one package reports whether generated symbols work there, with the evidence; the owner decides whether `tm-ios` ('Strings', `strings-and-accessibility.md`) and the two SwiftLint custom rules change.
- Refs: `.claude/skills/tm-ios/strings-and-accessibility.md` ('Strings'); `iosApp/.swiftlint.yml`; `iosApp/Packages/*/Sources/*/Localizable.xcstrings`.

### pr-description-ios-test-count
- Type: task
- Area: docs, scripts
- Order: 72
- Source: owner decision 2026-11-16 (iOS skills spike follow-up)
- Problem: The PR description's Tier 1 asks for test counts per module from `allTests`; the iOS package and UI test counts are not part of that method (`test-counts.md`). Reason for a record: a change to the PR description rules in `tm-pr-workflow` (a skill the owner decides on).
- Done when: `test-counts.md` says how the iOS package test count (and the UI test count) are read and reported, and the reviewer's check names it.
- Refs: `.claude/skills/tm-pr-workflow/test-counts.md`; `.claude/skills/tm-pr-workflow/commits-push-pr.md` ('PR description').

### healthkit-workout-with-route
- Type: task
- Area: iosApp, domain
- Order: 73
- Source: owner decision 2026-11-16 (iOS skills spike follow-up)
- Problem: Saving a finished activity to Apple Health as a workout with its route is not built. Parked as a product decision: it needs a new permission and its privacy text, and a choice of what is written.
- Done when: A decision (build or decline) with the data written and the permission text; if built, a plan under `docs/epics/`.
- Refs: `domain` `ActivityRecord`; `iosApp/TrailMetrics/Info.plist`; `ios-release-readiness`.

### gpx-export
- Type: task
- Area: domain, iosApp, androidApp
- Order: 74
- Source: owner decision 2026-11-16 (iOS skills spike follow-up)
- Problem: Exporting an activity as a GPX file is not built. Parked as a product decision: the format version, what is included (time, elevation, pauses) and the share path differ per platform.
- Done when: A decision (build or decline) with the contents of the file; if built, the writer in `domain` with `kotlin.test` coverage and a share action per platform.
- Refs: `domain` `ActivityRecord`; `data` activity history.

### units-setting
- Type: task
- Area: domain, iosApp, androidApp
- Order: 75
- Source: owner decision 2026-11-16 (iOS skills spike follow-up)
- Problem: There is no setting for metric or imperial units, and numbers, units and durations are formatted in the Kotlin `domain` today (`MetricsFormatter`) and by hand in the widget. The direction (owner decision 2026-11-16) is to format user-visible numbers per platform and locale, not in the domain; moving the existing formatting is a refactor that is not scheduled. Parked as a product decision.
- Done when: A decision on the setting (follow the locale or an in-app choice) and on who formats; then the formatting moved per platform with tests, and `shared-metrics-formatter-user-visible-strings` and `ios-hardcoded-number-formatting` resolved.
- Refs: `domain/src/commonMain/kotlin/dev/roozbahani/trailmetrics/domain/util/MetricsFormatter.kt`; `iosApp/TrackingWidget/TrackingLiveActivity.swift`; `shared-metrics-formatter-user-visible-strings`; `ios-hardcoded-number-formatting`; `tm-ios` ('Numbers, units and durations', `strings-and-accessibility.md`).

### ios-dynamic-type-beyond-the-pass
- Type: task
- Area: iosApp
- Order: 76
- Source: owner decision 2026-11-16 (iOS skills spike follow-up)
- Problem: The accessibility pass on the production screens (queue PR) covers labels, grouped metric cells, scaled sizes and Reduce Motion. Layouts at the largest Dynamic Type sizes (wrapping, scrolling, the Live Activity and widget) are not checked. Parked as a product and design decision.
- Done when: The largest accessibility sizes are checked on every screen and the widget, the layout decisions are made, and a UI test or audit covers them.
- Refs: `iosApp/Packages/*/Sources`; `iosApp/TrackingWidget/`; `tm-ios` ('Accessibility', `strings-and-accessibility.md`).

### store-assets
- Type: task
- Area: iosApp, androidApp
- Order: 77
- Source: owner decision 2026-11-16 (iOS skills spike follow-up)
- Problem: Store assets (icon set, screenshots, description, keywords, category) do not exist. Parked as a product decision; the Figma design system is the last item on the board.
- Done when: The assets exist for the stores the owner publishes to, and are named in the release plan of `ios-release-readiness`.
- Refs: `ios-release-readiness`; `figma-design-system`.

### ios-stop-intent-runs-in-the-app-process
- Type: task
- Area: iosApp/TrackingWidget, iosApp/TrailMetrics
- Order: 78
- Source: PR feature/ios-route-map-incremental-update
- Problem: Experiment of 2026-11-16 (simulator, iPhone, iOS 26.5, UI test tapping Stop on the lock screen, the intent logging its process): `StopTrackingIntent` as shipped, a type of the widget extension target only, ran `perform()` in the `TrackingWidgetExtension` process (pid 14322, bundle `dev.roozbahani.TrailMetrics.TrackingWidget`), which is why it posts a Darwin notification that only a live app process hears. With the same intent also compiled into the app target it ran in the app process (`TrailMetrics`, pid 14974); and with the app terminated first it ran in a new app process (pid 15728). The Stop button therefore does nothing when the app is not alive today, and a copy of the intent in the app target would let it reach the app, which then holds no `TrackingSessionManager` state until it restores the stored session. Reason for a record: a design decision (where the intent lives, what Stop means for a session the app has to restore first, the Darwin notification), and the result is of the simulator only.
- Done when: The owner decides whether the intent moves or is copied into the app target and what Stop does when the app was terminated; the check is repeated on a real device before the design is built.
- Refs: `iosApp/TrackingWidget/StopTrackingIntent.swift`; `iosApp/Packages/Tracking/Sources/Tracking/TrackingLiveActivityController.swift` (`registerStopNotificationObserver`).

### ios-accessibility-manual-pass
- Type: task
- Area: iosApp
- Order: 79
- Source: owner decision 2026-11-16 (open human checks of PR #322 and #325)
- Problem: Part of the epic `ios-release-readiness`. The accessibility pass of PR #325 is checked by `AccessibilityAuditUITests` (element descriptions and hit regions, run in the gate), but not Reduce Motion, the scaled zoom buttons at large text sizes, the widget's grouping on the lock screen or how the screens sound. Reason for a record: an owner decision of 2026-11-16 to track this pass here; it is the owner's manual pass on a device, needed before a release and not before a merge, and the owner decides when it is done.
- Done when: The owner has done a manual pass with VoiceOver, Reduce Motion and the largest text size: on Route the top bar and zoom buttons read "User Profile", "Reset", "Zoom in", "Zoom out"; in History and Details the metric cells read as label and value pairs and the type icon is skipped; with Reduce Motion on, Zoom in jumps and the maps follow a position without panning animation; at the largest text size the zoom buttons grow and stay tappable; the Live Activity on the lock screen reads each metric as one element; findings are fixed or declined, and this record is deleted.
- Refs: `iosApp/TrailMetricsUITests/Accessibility/AccessibilityAuditUITests.swift`; `iosApp/Packages/Route/Sources/Route/GMSMapView+ReduceMotion.swift`; `ios-release-readiness`; `ios-dynamic-type-beyond-the-pass`; `tm-ios` ("Accessibility", `strings-and-accessibility.md`).

### tracking-ui-timer-independent-of-location
- Type: task
- Area: domain, iosApp, androidApp
- Order: 80
- Source: PR #66 test
- Problem: The in-app elapsed time shows `metrics.elapsedMillis` from the tracking state, which is only re-emitted on location events. There is no ticker, so a stationary device freezes the timer and the display can jump (observed by 2 s).
- Done when: the displayed time ticks independently of location events on both platforms, without changing the domain's accounting of elapsed time.
- Refs: `TrackingSessionManager` (state emissions); Android `TrackingScreen` (`formatElapsedTime(metrics.elapsedMillis)`); iOS `MetricsDisplay`.

### ios-mainactor-run-hop-redundant
- Type: task
- Area: iosApp/Tracking, iosApp/History
- Order: 81
- Source: owner decision 2026-11-16 (iOS skills spike follow-up), item 7
- Problem: A temporary `MainActor.preconditionIsolated` before each of the three `await MainActor.run` hops (`HistoryViewModel.observe`, `TrackingViewModel.observeTrackingState` and `observeLocationIssues`) never fired: 7 hops in the History package tests (22 tests) and 64 in the Tracking package tests (89 tests) were already on the main actor, and the 9 UI tests passed with the probe in place (Xcode 27.1, iOS 26.5 simulator, packages in language mode 5). The location-issues hop was not reached by any test. `tm-ios` ("SKIE interop") and `tm-kmp-shared` say the resumption after `for await` is not guaranteed to be on the main actor. Reason for a record: an owner decision on a rule of two skills and on changing the view models, with the result of the simulator only.
- Done when: the owner decides whether the three hops are removed and the two skill sentences corrected (after a test of the location-issues hop and a device run), or kept as a defensive measure with the sentences reworded.
- Refs: `iosApp/Packages/History/Sources/History/HistoryViewModel.swift`; `iosApp/Packages/Tracking/Sources/Tracking/TrackingViewModel.swift`; `.claude/skills/tm-ios/SKILL.md` ("SKIE interop"); `.claude/skills/tm-kmp-shared/SKILL.md` ("SKIE and Swift-facing API design").

### android-ui-test-launch-seam
- Type: task
- Area: androidApp
- Order: 90
- Source: PR #210 and chat 2026-10-23
- Problem: Android has no launch-time seam (fakes for location, directions and storage injectable when the app starts, as iOS has with `UITEST_SEAM`) and, since the instrumented tier (`androidApp/app/src/androidTest`, the notification and Stop tests), an app-level UI-test target that runs the real graph but has no seam; its other UI tests are Robolectric tests per screen, so a flow across screens with the app's real navigation and Koin graph and fake inputs is not covered by any test. Recorded because the deleted `agentic-dev-loop` epic's Done when (1) was read as Robolectric tests only; it is a different subject from the PR that found it.
- Done when: such a seam exists for the `androidTest` target, and at least one flow across two screens runs in the local gate's Android UI run and fails when a binding or a navigation is broken (shown on a deliberately broken version). The design (instrumented test or Robolectric with the real graph) is stated in the PR and fits the `shared` Koin graph tests of #207.
- Refs: `docs/epics/agentic-dev-loop.md` (Done when item 1, deleted record); `docs/epics/ios-ui-tests.md`; `.claude/skills/tm-testing`; `shared-uitest`.

### release-build-links-debug-xcframework
- Type: task
- Area: iosApp, shared
- Order: 105
- Source: docs/epics/ios-ui-tests.md Q9 (PR #138), 2026-10-13
- Problem: `iosApp/Packages/SharedKit/Package.swift` points its `binaryTarget` at `shared/build/XCFrameworks/debug/TrailMetricsShared.xcframework` for every build configuration, and `scripts/build-kmp-framework.sh` builds only the debug XCFramework (`:shared:assembleTrailMetricsSharedDebugXCFramework`). So a Release build of the app links the debug Kotlin framework. That framework no longer contains the Swift test support or the iOS UI-test fakes: both live in `shared-uitest`, which is built only into a test-only variant of the framework (`docs/epics/ios-ui-tests.md`, D1), and `scripts/check-production-framework.sh` checks that the production framework has none of it. What remains is that the Release build links a debug-configuration framework. Measured on 2026-11-17 (Apple M4, Kotlin 2.4.10, warm caches): the release link of one slice (`:shared:linkReleaseFrameworkIosArm64`) takes 52 s against about 11 s for a debug link; the release arm64 static archive is 22.6 MB against 70.5 MB per debug slice (the debug XCFramework is 147 MB). The framework's bundle ID is set in `shared` and `shared-uitest` (`binaryOption("bundleId", ...)`); the Release path has to check that the release framework's debug info reaches the app's dSYM, so that Kotlin frames are symbolicated (`ios-crash-reporting-and-symbolication`); with the debug framework it does (2026-11-25: `dwarfdump --name <Kotlin function> TrailMetrics.app.dSYM` of a Release simulator build names the function and its Kotlin source file), and the dSYM is what the "Upload Crashlytics dSYM" phase sends.
- Done when: a Release app build links a release XCFramework that contains no test-support or UI-test code, shown by a command in the PR (for example a symbol check on the Release app binary), the Release app's dSYM still names the Kotlin functions with their Kotlin source files (the same `dwarfdump` check), and the gate and CI still build and test with the debug XCFramework.
- Refs: `iosApp/Packages/SharedKit/Package.swift`; `scripts/build-kmp-framework.sh`; `shared/build.gradle.kts` (`binaries.framework`); `shared-uitest/src/iosMain/kotlin/dev/roozbahani/trailmetrics/uitest/testsupport/SwiftTestSupport.kt`; `scripts/check-production-framework.sh`; `docs/epics/ios-ui-tests.md` (F4, D1, Q9); `.claude/skills/tm-ios/build-and-schemes.md` ("Build integration").

### ios-simulator-only-framework-slice
- Type: task
- Area: shared, scripts, iosApp
- Order: 106
- Source: spike kotlin-agent-skills 2026-11-17
- Problem: Needs the owner's design: it changes `scripts/build-kmp-framework.sh` and `SharedKit/Package.swift`, both protected, and the stamp semantics. Every Kotlin change builds both debug slices (device and simulator, about 21 s each on the Apple M4, measured 2026-11-17), although CI's `xcodebuild` and package tests and the gate use the simulator slice (`generic/platform=iOS Simulator`, `ARCHS=arm64`). A simulator-only XCFramework for simulator destinations would save one slice per rebuild (about a third of a cold framework build there, more on the CI runner). Questions for the design note: the stamp must record the slice set; a device build must still get the device slice; whether `SharedKit` keeps one `binaryTarget` path; what the Release path of `release-build-links-debug-xcframework` links.
- Done when: a design note under `docs/` (or in this record's PR) says whether to do it and how, with the before and after numbers of the real command; the owner decides.
- Refs: `scripts/build-kmp-framework.sh`; `iosApp/Packages/SharedKit/Package.swift`; `release-build-links-debug-xcframework`; `tm-kmp-shared` ("Kotlin/Native build cost"); `tm-ios` ("Build integration", `build-and-schemes.md`).

### swift-api-header-dump-in-gate
- Type: task
- Area: scripts, shared
- Order: 107
- Source: spike kotlin-agent-skills 2026-11-17
- Problem: Needs the owner's decision: an idea, and a new gate script (protected paths). The Swift-visible API of `TrailMetricsShared` is checked only by review (`tm-kmp-shared`, "`@Throws` policy", rule 6, and the PR's "Swift-visible API" list); `scripts/check-variant-api.sh` compares the test-only variant with production, not production with its past. A committed dump of the production header (or of SKIE's Swift interface), diffed in the gate, would show every Swift-visible API change mechanically, and the narrowing of the framework's exports would show up in review.
- Done when: the owner decides; if yes, a script with a self-test (in the gate and CI) fails when the dump differs from the committed one, and a PR that changes the API updates the dump and lists the change under "Swift-visible API".
- Refs: `scripts/check-variant-api.sh`; `shared/build.gradle.kts`; `tm-kmp-shared` ("`@Throws` policy"); `tm-pr-review`.

### ios-ci-package-tests-duration
- Type: task
- Area: CI, iosApp
- Order: 108
- Source: spike kotlin-agent-skills 2026-11-17
- Problem: Needs the owner's design: each way to shorten it changes how every package is tested in CI and in the gate (one `xcodebuild` for all packages against one per package, build once and test without building, a derived-data cache, parallel simulators), and trades CI minutes against isolation per package; the workflow and gate files are protected. In the four latest runs of `main` (2026-11-16), the step "Run iOS package tests" of the `ios-build` job took 377 to 603 s of a job of 683 to 1176 s. It runs `xcodebuild test` once per package with a `Tests/` directory, and each run resolves, builds and links the packages and the test-only framework variant again.
- Done when: the time is attributed (resolution, build, simulator boot, tests, per package) from a CI log, and the owner has the options with expected savings (one `xcodebuild` for all packages, build once and test without building, a cache of derived data, parallel simulators); a PR does the chosen one with before and after step times.
- Refs: `.github/workflows/ci.yml` (`ios-build`, step "Run iOS package tests"); `scripts/pre-push-check.sh` (the gate's package-test step); `tm-ios` ("Build integration", `build-and-schemes.md`).

### tracking-location-path-double-clock-read
- Type: task
- Area: domain
- Order: 140
- Source: PR #66 drift
- Problem: In `TrackingSessionManager.observeLocation`, each `LocationUpdate.Success` reads `clock.elapsedRealtimeMillis()` twice: once for `speedCalculator.calculate` and once for `TrackingEvent.LocationReceived`. Speed and accounting can therefore see slightly different timestamps for the same event.
- Done when: the clock is read once per event and reused, with a test.
- Refs: `domain` `TrackingSessionManager.observeLocation`, `SpeedCalculator`.

### polyline-decoder-invalid-characters
- Type: task
- Area: data
- Order: 160
- Source: PR #68 review
- Problem: `decodePolyline` rejects only truncated input. Characters outside the valid encoded-polyline range (`?`..`~`) are not rejected: `code - 63` is used as-is and silently decodes to garbage coordinates instead of failing.
- Done when: invalid characters throw `IllegalArgumentException` (which `DirectionsRepositoryImpl` already maps to `DirectionsApiError`), with tests.
- Refs: `data` `decodePolyline` / `decodeValue`; `PolylineDecoderTest`; `DirectionsRepositoryImpl.getClosedRoute`.

### test-data-remaining-untested-classes
- Type: task
- Area: data
- Order: 170
- Source: PR #70
- Problem: After the directions tests, `data` is at 44.38% line coverage (142/320, Android host Kover report, generated code excluded). The five biggest gaps (uncovered lines, nested/lambda classes merged into their source class) all have 0% covered: `AndroidLocationRepositoryImpl` (49), `TrackingService` (44), `di/CommonTrackingModule` (14), `di/NetworkModule` (10), `di/UseCaseModule` (10). iOS-only code (`IosLocationRepositoryImpl`, `IosTrackingServiceLauncher`) isn't in the report at all, because Kover can't measure the iOS run.
- Done when: those classes have tests (or a documented reason why one can't be tested on the host), and the `data` Kover floor is raised in the same PR.
- Refs: `data` `location/AndroidLocationRepositoryImpl`, `tracking/TrackingService`, `di/CommonTrackingModule`, `di/NetworkModule`, `di/UseCaseModule`; `data/build.gradle.kts` `kover.reports.verify`; `tm-testing`.

### android-tracking-notification-content
- Type: task
- Area: data
- Order: 190
- Source: PR #66 test
- Problem: The Android foreground tracking notification (built in `data`'s androidMain `TrackingService.buildNotification`) shows only "Tracking..."/"Paused - " plus distance. It has no elapsed time or other metrics. No doc or skill records whether that is intentional.
- Done when: it shows elapsed time and key metrics, or the decision not to is documented.
- Refs: `data/src/androidMain` `TrackingService.buildNotification`.

### swiftlint-disable-requires-reason-rule
- Type: task
- Area: iosApp
- Order: 194
- Source: agentic-dev-loop run 18 review (PR #104), 2026-10-05
- Problem: the repo's convention is `// swiftlint:disable:next <rule> - <reason>`, but a disable comment with no reason, or with an empty one (` - ` and nothing after it), still passes `--strict` (seen with SwiftLint 0.65.1 on a fixture: exit 0, 0 violations); only review notices.
- Done when: a check rejects a `swiftlint:disable` comment (any rule, `:next`, `:this`, `:previous` and the block forms) that has no ` - <reason>` text, every existing suppression under `iosApp/` complies or the PR lists the ones that do not with the human's decision, and the check is shown failing on an example without a reason and passing with one (a SwiftLint custom rule on comments, or a small script, whichever the PR justifies).
- Refs: `iosApp/.swiftlint.yml`; `tm-ios` ("SwiftLint", `swiftlint.md`, suppression convention).

### wait-until-cancellation-spin
- Type: task
- Area: iosApp/TestSupport
- Order: 196
- Source: agentic-dev-loop run 18 review (PR #104), 2026-10-05
- Problem: `waitUntil` in TestSupport polls with `try? await Task.sleep(for: .milliseconds(10))`; when the calling test task is cancelled, `Task.sleep` throws at once and the `try?` drops that, so the loop spins without any delay until its deadline (up to 120 seconds, `coldStartTimeout`, for the first wait in a test process). No failure is hidden, but the test burns CPU instead of stopping. The `optional_try` annotation on that line says only that the deadline still ends the wait.
- Done when: `waitUntil` stops promptly when its task is cancelled (for example it checks `Task.isCancelled` or lets the cancellation error end the wait), a test shows it (red before, green after), and the `swiftlint:disable:next optional_try` comment is updated or removed to match the code.
- Refs: `iosApp/Packages/TestSupport/Sources/TestSupport/Support/WaitUntil.swift`; PR #104.

### selftest-scratch-repo-hardening-other-scripts
- Type: task
- Area: scripts
- Order: 197
- Source: fix of the skill rule-change self-test cleanup PR, 2026-10-06
- Problem: `check-kover-floors.py`, `check-protected-paths.py` and `classify-changes.sh` build scratch git repositories and commit in them without `gc.auto=0` and `maintenance.auto=false`, and remove them with a bare `tempfile.TemporaryDirectory` or `rm -rf`; `check-ios-scope.py` has `gc.auto=0` but not `maintenance.auto=false`. The same "Directory not empty" failure that once stopped the skill rule-change self-test in CI could hit any of them.
- Done when: each gets the same git flags and the same resilient cleanup as `check-skill-rule-changes.py` (or one shared approach the human agrees), with its self-test still passing.
- Refs: `scripts/check-kover-floors.py`; `scripts/check-protected-paths.py`; `scripts/classify-changes.sh`; `scripts/check-ios-scope.py`; `scripts/check-skill-rule-changes.py` (`remove_scratch`).

### build-kmp-framework-self-test
- Type: task
- Area: scripts
- Order: 201
- Source: chore/script-self-tests scan for scripts without a `--self-test`, 2026-10-22
- Problem: `scripts/build-kmp-framework.sh` decides by an input hash and a variant marker whether to rebuild the XCFramework, and fails an Xcode `--build-phase` call after a rebuild instead of linking a stale copy. None of this has a self-test, so a regression in the hash gating, the variant switch or the `--build-phase` exit would show up only as a stale framework in an iOS build. A self-test needs the Gradle call stubbed (a fake `gradlew` in a scratch tree), which is a design choice of its own.
- Done when: a `--self-test` runs the script in a scratch tree with a fake `gradlew` and checks: a first build runs Gradle, an unchanged second run skips it, a changed input or the other variant rebuilds, `--build-phase` after a rebuild exits non-zero with the message, an unknown option and an unknown variant exit 2; it passes on bash 3.2 and bash 5 (or `sh`, per the script's shebang), and is wired into the gate, CI's `tooling` job and CODEOWNERS like the other self-tests; it was shown failing against a deliberately broken version.
- Refs: `scripts/build-kmp-framework.sh`; `scripts/pre-push-check.sh`; `.github/workflows/ci.yml`; `.github/CODEOWNERS`.

### simulate-route-self-test
- Type: task
- Area: scripts
- Order: 202
- Source: chore/script-self-tests scan for scripts without a `--self-test`, 2026-10-22
- Problem: `scripts/simulate-route.sh` (the developer tool that walks an iOS Simulator along a route through `xcrun simctl location`) interpolates points between waypoints and paces them to a speed, and has no self-test, so a regression in the interpolation, the pacing or the CSV parsing would show only as a wrong walk in a simulator. It needs `xcrun`, so a test must put a fake `xcrun` first on `PATH`.
- Done when: a `--self-test` runs the script against a fake `xcrun` that records its calls and a short CSV in a `*-fixtures/` folder, and checks the interpolated points, the pace, the loop back to the first waypoint (the run bounded by the fake) and the errors for a missing or malformed file; it passes on bash 3.2 and bash 5, is wired into the gate and CODEOWNERS (CI's `tooling` job has no simulator but needs none), and was shown failing against a deliberately broken version.
- Refs: `scripts/simulate-route.sh`; `scripts/routes/sample-loop.csv`; `scripts/pre-push-check.sh`; `.github/CODEOWNERS`.

### flake-ios-ui-route-map-press-lost
- Type: task
- Area: iosApp/TrailMetricsUITests
- Order: 220
- Source: CI run 39049148407 (main, push, head 46a3636, the merge of #161), 2026-10-17; escalated at count 3 from the entry `ios-ui-route-map-press-lost` in `CI_FLAKES.md`
- Problem: `iOS — run UI tests` (since renamed `iOS 3 — run UI tests (after 2a)`) failed (exit 65) twice on `main`, in two Route tests, with the same message "Generate button not enabled after 3 waypoints" (the 10 s wait for `isEnabled` timed out in the same `XCTAssertEqual` of `XCUIApplication+RouteMap.swift`): `RouteGenerateTwiceUITests.test_generateTwice_requestsDirectionsOnce` (run 39049148407: test about 160 s, step about 802 s) and `RouteGenerateThenResetUITests.test_resetWhileGenerating_leavesACleanScreen` (run 39074545852: test about 92 s, step 510 s); the other five tests passed in both. #161 changed only comments in `scripts/classify-changes.sh` and `scripts/pre-push-check.sh` and one fixture `expect` line, and #162 only two skills and the epic text; none is an input of the iOS jobs. The cause is unknown. A slow runner or map is a hypothesis that the timings support but do not prove: in the first run the `route.map` check took about 77 s and the map presses 3 to 12 s; in the second the check took about 1 s and one of three presses took about 39 s (the others 8 and 4 s). The first suite started 302 s and 195 s after `xcodebuild` in the two failed runs and 126 to 357 s in the ten executions of the last 100 runs of `ci.yml`, so a late start does not tell failing runs from passing ones. In those 100 runs the job ran its tests 10 times (6 on `main`, 4 on PR branches, all four green; 5 more were skipped or cancelled) and failed 2, both on `main`, both Route tests; the step took 370 to 802 s; 3 of the 60 test executions took over 100 s (143 s `deleteConfirmedTwice`, 135 s `resetWhileGenerating`, 160 s the first failure). Before the split the same step ran 23 times in the single iOS job; one of those failed after 72 s (2026-10-14, not investigated). The two result bundles show that at the failure the screen had no red waypoint marker and Generate was disabled, so fewer than 3 waypoints existed; which press was lost, and why, is unknown. The log has no `GMS`, network or tile line. The location-permission alert appears in `RouteGenerateThenResetUITests` in every run (it is the first Route test), so it is not the cause by itself. The helper `addRouteWaypoints` reported any press problem as "Generate button not enabled"; since the change `test(ios-ui): make the Route map-press failures say which press was lost` it reports the press (k of N), the waypoint count the app showed, the press timings and a screenshot, so the next red run will say which press was lost. Risk noted: the Route tests depend on the location-permission state left by an earlier test (the tests run alphabetically and the alert appears only in the first Route test). A third failure came with run 39137921296 (the push of the #167 merge to `main`): `RouteGenerateTwiceUITests.test_generateTwice_requestsDirectionsOnce` failed with "map press 1 of 3 did not add a waypoint: count 0, expected 1 (press took 12.55 s, 23.50 s since the helper began)". The earlier two failures had no per-press diagnostic, so it is unproven that they were press 1. The result bundle of the third failure shows the map blank with no tiles, no permission alert or other overlay, the green start pin, no red waypoint marker, the probe overlay reading `waypoints=0` after two refreshes (so the app was responsive), Generate visible and disabled, and the press point clear of every overlay. The log shows the app launch to the automation session taking 56.5 s (29 s in the first test of that run) and the synthesized press event taking about 8 s; there is no XCUITest error, no interrupting element and no Maps, network or tile line. Counts: 2 failures in the 11 executions that ran tests before the diagnostics and 1 failure in the 4 executions after them (1 lost press in 12 helper calls). Press durations of passing helper calls range from about 1.6 s to 42 s, so a slow press alone does not separate failing from passing. Hypotheses: a load-related loss of the press is probable, not proven (there is no app-side evidence that the event reached the map); that the map's gesture handling was not ready although `route.map` exists is unknown (there is no app-side signal); that `didLongPressAt` is a no-op in some state is not supported by the code (it has no state guard); an alert or overlay is ruled out for this execution. The "use your location?" system alert appears once per execution and is dismissed by the default interruption handler; its origin was not found (UI-test mode replaces the location repository by a fake). The change `test(ios-ui): add Route waypoints through a seam, keep one map long-press test` makes three tests (`RouteGenerateTwiceUITests`, `RouteGenerateThenResetUITests`, `TrackingFinishTwiceUITests`) add their waypoints through the probe's seam button and keeps one test, `RouteMapLongPressUITests`, on the real long press: the dependency of the other three on the press is gone, the press path itself is not fixed, and the cause stays unknown. Two later red runs were app launch timeouts in the first Details tests, not this flake (in the last 100 runs of `ci.yml` the UI-test job ran its tests 36 times: 31 green, 5 red, 3 of them this Route flake and 2 launch timeouts); they are the entry `ios-ui-details-launch-timeout` in `CI_FLAKES.md`.
- Done when: the flake no longer fails or the runner/test is changed so it cannot, shown on 5 consecutive local runs of the iOS UI suite (the gate's iOS UI tests step, or the full run on `main`: `scripts/main-ui-run.sh`; the CI job that this record names was removed, UI flakes are counted by `scripts/ui-flake.sh`).
- Refs: CI runs 39049148407 and 39074545852; `RouteGenerateTwiceUITests.test_generateTwice_requestsDirectionsOnce`; `RouteGenerateThenResetUITests.test_resetWhileGenerating_leavesACleanScreen`; CI run 39137921296; `RouteMapLongPressUITests.test_longPress_addsAWaypoint`; `iosApp/TrailMetricsUITests/Route/XCUIApplication+RouteMap.swift`; `docs/epics/ios-ui-tests.md` (D6); `.claude/skills/tm-testing/SKILL.md` ("Flakes (D6)"); `CI_FLAKES.md`.

### ios-ui-location-permission-alert-origin
- Type: task
- Area: iosApp/TrailMetricsUITests
- Order: 225
- Source: board record flake-ios-ui-route-map-press-lost and chat 2026-10-18
- Problem: The "use your location?" system alert has so far been seen only in CI logs or result bundles, not locally. A local look found no origin: the production `IosLocationRepositoryImpl` is ruled out (the UI-test module overrides all five bindings that would create it, and `UiTestEntryTest` asserts it is never created in UI-test mode), no Swift file requests location, and on a fresh local simulator (iPhone 17, iOS 26.5, privacy reset, app uninstalled) the alert did not appear in `RouteGenerateTwiceUITests` alone or in the three Route classes run in order; a temporary interruption monitor never fired. The Route tests may still depend on the permission state an earlier test left. The CI logs read since then show the alert in every UI-test log (red and green), only in `RouteGenerateThenResetUITests`, the first Route test, about 9 to 10 s into the test, and the default interruption handler dismisses it with "Don't Allow". It does not appear in the Details tests that run before it, so something in the Route screen's start triggers it; the origin is still not found.
- Done when: the alert is captured on CI (an interruption monitor in the Route tests that records its label, or a failing run's result bundle), and the Route tests no longer depend on which ran first, either by `XCUIApplication.resetAuthorizationStatus(for: .location)` before launch or by handling the alert explicitly in each Route test. If CI's simulator itself needs a reset step, that touches the protected CI workflow and the human decides.
- Refs: `RouteGenerateThenResetUITests` and the other Route tests; `iosApp/TrailMetricsUITests/Route/XCUIApplication+RouteMap.swift`.

### shared-metrics-formatter-user-visible-strings
- Type: task
- Area: shared, iosApp
- Order: 226
- Source: PR for ios-localizable-strings
- Problem: `domain/.../util/MetricsFormatter.kt` (`formatDistance`, `formatSpeed`, `formatCalories`) returns finished user-visible texts with the unit words and the "no value" placeholder inside the Kotlin string ("1.50 km", "-- km/h", "-- kcal"). iOS shows them verbatim (`Text(value)` in `HistoryMetricCell`, `TrackingMetricCell`), so they cannot come from a String Catalog and a translation of the unit words is impossible on iOS. Android uses the same functions. Left alone in the localization PR because the fix needs a design decision: return the number and unit as values and let each platform format them, or pass localized unit labels in.
- Done when: the decision is made (an ADR or a plan if it changes the shared API), and iOS and Android both show these values from their own localizable resources; the iOS catalogs carry the unit and placeholder texts.
- Refs: `domain/src/commonMain/kotlin/dev/roozbahani/trailmetrics/domain/util/MetricsFormatter.kt`; `iosApp/Packages/*/Sources` (`formatDistance` callers); `ios-hardcoded-number-formatting`.

### ios-hardcoded-number-formatting
- Type: task
- Area: iosApp, shared
- Order: 227
- After: shared-metrics-formatter-user-visible-strings
- Source: PR for ios-localizable-strings
- Problem: Number and unit formatting is hardcoded and ignores the user's locale: the Live Activity (`TrackingWidget/TrackingLiveActivity.swift`) re-implements the shared formatter in Swift with `String(format: "%.2f km")`, `"%.1f km/h"`, `"\(Int(meters)) m"`, `"-- km/h"` and a fixed `%02d:%02d`; the Kotlin `formatFixed` always writes a `.` as the decimal separator. A comma-decimal locale, or miles for a user who expects them, gets the English-US shape. Dates are not affected: `ActivityRow.dateFormatter` uses `DateFormatter` with `.medium`, which follows the locale. Found, not fixed, in the localization PR (formatting is a separate topic).
- Done when: distances, speeds, calories and durations on iOS (app and widget) are formatted with the user's locale (`Measurement`/`FormatStyle`, or values formatted by the platform), or the decision to keep metric units fixed is recorded; the widget no longer duplicates the shared formatter by hand.
- Refs: `iosApp/TrackingWidget/TrackingLiveActivity.swift` (`formatDistance`, `formatSpeed`); `domain/.../util/MetricsFormatter.kt` (`formatFixed`); `shared-metrics-formatter-user-visible-strings`.

### skill-folder-front-matter-detection
- Type: task
- Area: scripts
- Order: 231
- Source: PR for pr-review-item-3-reference-skill-files
- Problem: A change to the YAML front matter of a `SKILL.md` or reference file in the five ownerless skill folders (`tm-ios`, `tm-android`, `tm-kmp-shared`, `tm-testing`, `tm-robustness`) is escalated by `tm-pr-review` item 3 only because the reviewer reads the diff. No script detects it, so a missed read lets front matter (which can carry settings) change without a human.
- Done when: a script under `scripts/` with a self-test (in the gate and CI) reports a diff that changes the front matter of a Markdown file in those folders, and item 3 of `tm-pr-review` points to its output instead of asking the reviewer to read for it. Both are protected paths: a human PR.
- Refs: `.claude/skills/tm-pr-review/SKILL.md` (item 3); `scripts/check-protected-paths.py` (`UNOWNED_PATTERNS`); `scripts/check-skill-rule-changes.py`.

### tracking-location-update-path-cost
- Type: task
- Area: domain, data, androidApp/feature-tracking, iosApp/Tracking
- Order: 241
- Source: PR for tm-robustness-skill
- Problem: Every location update (every 3 s on Android, every callback on iOS with no `distanceFilter`) copies the whole path (`path + coordinates` in `UpdateTrackingStateUseCase`), emits a new state, and the Android polyline is rebuilt from the full list (`RoutePolyline`, `remember(points)`); nothing is conflated or sampled, and both platforms request the highest accuracy for the whole session. Cost grows with session length; the right sampling and accuracy are a product and battery decision.
- Done when: the path grows without a full copy per update (or is sampled by distance), the UI receives conflated updates, and the owner's accuracy and interval choice is recorded in `tm-robustness` P4 and P6.
- Refs: `domain/.../usecase/UpdateTrackingStateUseCase.kt`; `data/src/androidMain/.../location/AndroidLocationRepositoryImpl.kt`; `data/src/iosMain/.../location/IosLocationRepositoryImpl.kt`; `androidApp/core-ui/.../map/RoutePolyline.kt`; `tm-robustness` P4, P6.

### history-query-index-and-columns
- Type: task
- Area: data
- Order: 242
- Source: PR for tm-robustness-skill
- Problem: `tbl_activities` has no index on `startedAtEpochMillis`, which `ActivityDao.observeAll` sorts by, and the list query is `SELECT *`, so the history screen loads every row including both coordinate lists for the whole table (`tm-robustness` P5). An index is a Room schema change (`tm-kmp-shared`, "Changing the database schema") and a list projection changes the repository interface, so it is a task of its own.
- Done when: the sorted column has an index with its migration and test, and the history list reads only the columns it shows (or the cost is measured and accepted).
- Refs: `data/src/commonMain/.../local/entity/ActivityEntity.kt`; `.../local/dao/ActivityDao.kt`; `tm-robustness` P5.

### ios-snapshot-stored-at-full-resolution
- Type: task
- Area: iosApp/Tracking
- Order: 244
- Source: PR for snapshot-save-off-main-thread
- Problem: The iOS map snapshot is rendered at the map view's full bounds and screen scale and stored as that PNG (`renderMapSnapshot`, `writeMapSnapshot` in `MapSnapshotSaver.swift`), while Android scales to 600 px wide (`saveSnapshotToFile`). The stored file is several times larger on iOS (`tm-robustness` M5). Changing the stored size or format is a product decision about what the history screens show, so it is not made in the PR that moved the save off the main thread.
- Done when: the owner has decided the stored snapshot size, and iOS stores the same size as Android (or the difference is recorded as intended in `tm-ios`).
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/MapSnapshotSaver.swift`; `androidApp/feature-tracking/.../util/MapSnapshotSaver.kt`; `tm-robustness` M5.

### ios-snapshot-request-guard-test-seam
- Type: task
- Area: iosApp/Tracking
- Order: 245
- Source: PR for snapshot-save-off-main-thread
- Problem: The iOS Finish snapshot request in `TrackingMapView.updateUIView` has no test: the once-per-request guard (`handledSnapshotRequestID`), the task cancelled in `dismantleUIView`, and the dropped result for an old request run inside a `UIViewRepresentable` over a `GMSMapView`, which no package test can render or drive, and the iOS UI tests have no scenario that reaches the map snapshot. A seam is needed, for example the request handling moved into a small type that takes the render and the writer as closures, so a package test can call it. That is a design choice for the owner, so it is not made in the PR that moved the save off the main thread (`tm-pr-workflow` Tier 2, reason 2).
- Done when: the request handling (handle a request id once, cancel on teardown, drop a result whose request is no longer current, reset the request after delivery) is reachable from a Swift package test or a UI-test scenario, and tests cover each of the four.
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/TrackingMapView.swift`, `MapSnapshotSaver.swift`, `TrackingView.swift` (`finishTracking`); `tm-pr-workflow` Tier 2; `tm-testing`.

### flake-ios-ui-details-launch-timeout
- Type: task
- Area: iosApp/TrailMetricsUITests
- Order: 247
- Source: CI runs 39425719146 and 40122507751 (main, push); escalated at count 3 from the entry `ios-ui-details-launch-timeout` in `CI_FLAKES.md`
- Problem: `iOS 3 — run UI tests (after 2a)` failed on `main` with `DetailsDeleteTwiceUITests.test_deleteConfirmedTwice_deletesOnce` "Failed to launch" (73 s) in `XCUIApplication+Scenario.swift`, twice on pushes (2026-10-20, 2026-10-24) and once on a pull request; `DetailsFailedDeleteUITests` also failed to launch ("Failed to get background assertion") in the 2026-10-24 run. No test body ran. Later runs with the same tests were green. Cause not shown; the step boots the simulator with `simctl bootstatus -b` since #179 and the 2026-10-24 failure happened after it.
- Done when: the flake no longer fails or the runner/test is changed so it cannot, shown on 5 consecutive local runs of the iOS UI suite (the gate's iOS UI tests step, or the full run on `main`: `scripts/main-ui-run.sh`; the CI job that this record names was removed, UI flakes are counted by `scripts/ui-flake.sh`).
- Refs: CI runs 39425719146 and 40122507751; `iosApp/TrailMetricsUITests/Support/XCUIApplication+Scenario.swift`; `CI_FLAKES.md` entry `ios-ui-details-launch-timeout`.

### local-review-hook-shell-blind-spots
- Type: task
- Area: scripts/claude-hooks
- Order: 250
- Source: PR for local-review-gate (owner decision: audit 61)
- Problem: `scripts/claude-hooks/require-local-review.sh` reads the command text, so it cannot see a push built by shell syntax it does not parse: `$'git'`, `\git`, a variable-built or `eval`ed command, a script the agent writes and runs, and a `cd` that may not run (`false && cd x; git push`, which the linear reading applies anyway). Other points the reviewers raised, left for audit 61 by the owner: `.claude/settings.json` itself is not guarded against edits by the hook (a guard would block the owner's own protected tasks, so it is left to the owner); any command containing the word `local-reviews` or a `cd`/`pushd`/`popd` token before a push (a branch named `cd`) blocks even when harmless. A separate mechanism than command-text matching (for example the credential helper or a `pre-push` check the human installs) is the only complete fix; this is a human design decision.
- Done when: the owner has decided in audit 61 which of these to close and how (a stronger mechanism, or accepting the limits in the hook header), and the chosen ones are done or the record is deleted.
- Refs: `scripts/claude-hooks/require-local-review.sh` (header "Limits"); CI reviewer findings on PR #233.

### reviewer-misses-main-actor-task-blocking
- Type: task
- Area: skills
- Order: 260
- Source: PR for tm-robustness-d7-main-actor-task
- Problem: The local `pr-reviewer` missed the #219 case (`discardSnapshotFile`, a `FileManager.removeItem`, called in the cancel branch of a `Task { }` inside `TrackingMapView.updateUIView`, a main-actor context) in two scratch runs on the commit before the fix (`428444c`, base `c19d5e1`), with `tm-robustness` D7 in the tree both times. Run 1 (first D7 wording) cited D7/C1 but only as `[important]` for `snapshotDirectory()` ("cheap and not a real blocker") and said nothing about `discardSnapshotFile`; run 2 (D7 tightened once to say every statement of the `Task` body counts) had no finding on the `Task` body and did not cite D7. The CI reviewer found the case on the real PR, through C1 and D6. Two runs are a small sample, and the reviewer's output varies between runs. A text check cannot replace it: in #219 the `FileManager` call was inside `discardSnapshotFile`, called from a nested `if` of the `Task` body. `tm-pr-review` is a protected path, so a checklist change is not made here.
- Done when: audit 61 has compared the local and the CI reviewer on this diff and decided whether a concurrency-specific checklist item or a fixed `TASK` input (the local run got the PR title and description as of the commit, the CI run gets the final description) closes the gap, and the chosen change is done or the record is deleted.
- Refs: `.claude/skills/tm-robustness/SKILL.md` (D7); `.claude/skills/tm-pr-review/SKILL.md` (item 15); PR #219.

### local-reviewer-reads-working-tree-rules
- Type: task
- Area: skills
- Order: 280
- Source: PR for review-task-rehearsal (task 61a, decision 5)
- Problem: The local `pr-reviewer` reads the PR's own `.claude/` and `CLAUDE.md` files from the working tree, while CI's reviewer reads the base's copies (the "Build review inputs" step replaces them), so a PR that edits a skill is judged by the edited skill locally and by the old one in CI. It showed on #234: rule D7 was visible only locally. The `TASK` header that `scripts/review-task.sh` prints repeats CI's sentence that the working tree holds the base's copies, which is not true for a local run. This is an owner decision, not a same-subject fix.
- Done when: the owner decides whether the local input builder copies the base's instruction files into a scratch tree like CI does, and the skills and `scripts/review-task.sh` say what the decision is.
- Refs: `.github/workflows/pr-review.yml` ("Build review inputs"); `scripts/review-task.sh`; `.claude/skills/tm-pr-review/SKILL.md` ("Orchestrator's part"); PR #234.

### tracking-session-store-failures-not-surfaced
- Type: task
- Area: domain, data
- Order: 300
- Source: sweep tm-robustness
- Problem: `tm-robustness` E4 (blocking). A failed write or restore of the in-progress tracking session is only logged. `TrackingSessionManager.persist` catches the store's exception and calls `logger.debug` ("Saving the session failed"), and tracking goes on; if every write fails, process death loses the recorded path and the user was never told. `handleRestart` (`RestartAction.kt`) turns a `restore()` that throws after a `START_STICKY` restart into `StopSilently`: the service stops, recording ends, no notice. Count 2. Both code comments state the choice ("No user action can fix a failed write"; "A restore that throws is logged and ends like an empty one"), so whether to surface these failures (an event like `locationIssues`, a notice) is the owner's decision; recorded, not fixed.
- Done when: the owner decides. If surfaced: a failing `TrackingSessionStore.save` reaches the UI as an event or state, and a throwing restore in `handleRestart` leaves a notice, each asserted in `TrackingSessionManagerTest` and `RestartActionTest`. If not: `tm-robustness` E4 names these two paths as accepted exceptions.
- Refs: `domain/src/commonMain/.../tracking/TrackingSessionManager.kt` (`persist`); `data/src/androidMain/.../tracking/RestartAction.kt` (`handleRestart`); `domain/src/commonTest/.../tracking/TrackingSessionManagerTest.kt`; `data/src/androidHostTest/.../tracking/RestartActionTest.kt`; `tm-robustness` E4.

### finished-session-discard-control
- Type: task
- Area: domain, androidApp/feature-tracking, iosApp/Tracking
- Order: 320
- Source: review of PR #358 (owner request, 2026-11-19)
- Problem: A session that stops by itself at the route's end, or a restored finished one, offers only Save (the finish card's "Finish") on both platforms. Since PR #358, Start is not offered over it on either platform, because starting would replace the unsaved recording. If the end of the recording is bad (for example a bad GPS fix), the user has no way to get rid of it: they must save it, or leave the screen and keep it stored, which is offered again as a finished session and blocks starting a new activity. The route-completion epic makes a session end by itself also with the phone locked, so this state will be reached more often. Reason for a record: whether to offer Discard in the finished state is a product decision for the owner, not an agent follow-up.
- Done when: the owner decides. If yes: `domain`'s `TrackingControls` gets a `canDiscard` rule for `Finished` (one rule, `availableControls`, with `kotlin.test` cases for every state against it), both ViewModels only show it (a Discard control on the finish card, the same on both platforms, with a confirmation that says the recording is deleted), `discard()` clears the stored session as it does after a save, each platform has an adapter test and a test that a discarded finished session leaves Idle and offers Start, and this record is deleted. If no: the decision and its reason are written in `tm-android`/`tm-ios` or the PR that closes it (a finished session is saved or kept), and this record is deleted.
- Refs: `domain/.../model/TrackingControls.kt` (`canSave`, `canStop`); `TrackingSessionManager.discard`; Android `TrackingScreen` (the finish card); iOS `TrackingView` (`finishCard`).

### live-activity-throttle-uses-wall-clock
- Type: task
- Area: iosApp/Tracking
- Order: 330
- Source: sweep tm-kmp-shared
- Problem: `tm-kmp-shared` "Time": durations are measured with the monotonic clock, and two wall-clock reads are never subtracted (the skill gives no severity, read here as `important`). `TrackingLiveActivityController.update` throttles with `Date()` and `now.timeIntervalSince(lastUpdateDate)`. If the system time moves back (a manual change, a network time correction), the difference stays below `minimumUpdateInterval` and the Live Activity drops every update until the wall clock catches up. Count 1. Recorded, not fixed: this sweep changes no code, and the fix (the shared `Clock.elapsedRealtimeMillis()`, or `ContinuousClock` in Swift) is a choice for the iOS change.
- Done when: `grep -n 'Date()' iosApp/Packages/Tracking/Sources/Tracking/TrackingLiveActivityController.swift` shows no read used for the throttle, and a package test drives the throttle through an injected clock, including a clock that goes back.
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/TrackingLiveActivityController.swift` (`update`, `minimumUpdateInterval`); `tm-kmp-shared` ("Time").

### android-mainactivity-field-injection
- Type: task
- Area: androidApp/app
- Order: 360
- Source: sweep tm-android
- Problem: `tm-android` "Koin" forbids field injection and `KoinComponent` in application code (no severity given; read as `important`). `MainActivity` field-injects three dependencies with `by inject()`: `trackingSessionManager`, `applicationScope` (`inject(APPLICATION_SCOPE)`) and `logger`. Count 3, one file. The skill's own exception names only `TrackingSessionManager`, so two of the three are not even listed (see `android-skill-koin-and-count-text-stale`). Known deviation of `tm-android` with no board record until now. Recorded, not fixed: an Activity is not constructed by Koin, so the replacement (a ViewModel that holds the Stop handling, or `koinInject()`/`get()` at the composition root) is a design choice and changes `MainActivity` and its tests.
- Done when: `grep -n 'by inject' androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/MainActivity.kt` returns nothing, the Stop-intent handling still discards the session in the application scope, and `tm-android`'s Koin exception line is removed.
- Refs: `androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/MainActivity.kt` (`trackingSessionManager`, `applicationScope`, `logger`, `handleStopTrackingIntent`); `androidApp/app/src/test/`; `tm-android` ("Koin", "Known deviations").

### android-viewmodels-koin-lambda-form
- Type: task
- Area: androidApp/feature-route, androidApp/feature-history
- Order: 370
- Source: sweep tm-android
- Problem: `tm-android` "Koin" prefers `viewModelOf(::X)` and allows the lambda form only for a factory method, a qualifier, runtime parameters or post-construction setup (no severity given; read as `important`). `routeModule` registers `RouteViewModel` and `historyUiModule` registers `HistoryViewModel` with `viewModel { X(a = get(), b = get()) }`: only plain constructor arguments, none of the four reasons. Count 2. `DetailsViewModel` and `TrackingViewModel` take runtime parameters and keep the lambda form correctly. Recorded, not fixed: a change to Koin files, small but of another subject than this sweep.
- Done when: `grep -n 'viewModel {' androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/di/RouteModule.kt` returns nothing and `HistoryUiModule.kt` uses `viewModelOf(::HistoryViewModel)` for `HistoryViewModel`; the module's Koin graph tests still pass.
- Refs: `androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/di/RouteModule.kt`; `androidApp/feature-history/src/main/kotlin/dev/roozbahani/trailmetrics/feature/history/di/HistoryUiModule.kt`; `androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/di/AppModule.kt` (the `viewModelOf` pattern); `tm-android` ("Koin").

### android-screen-overload-delegates-to-root
- Type: task
- Area: androidApp/feature-route, androidApp/feature-tracking, androidApp/feature-history, androidApp/app
- Order: 380
- Source: sweep tm-android
- Problem: `tm-android` "Presentation layer" names `<Screen>Screen` the stateless composable (`state` + `onAction`, no ViewModel reference) and `<Screen>Root` the one holding the ViewModel. Each of the four screen files also has a public `<X>Screen(...)` overload that only calls `<X>Root`, so every screen name is declared twice with different meanings (`RouteScreen`, `TrackingScreen`, `HistoryScreen`, `DetailsScreen`). Count 4. It is a known deviation of `tm-android` ("kept so MainActivity's NavHost call sites didn't change") with no board record until now. Recorded, not fixed: the fix changes the four NavHost call sites in `MainActivity` and the UI tests that call the overloads.
- Done when: `grep -rn 'NavHost entry point' androidApp/feature-route/src/main androidApp/feature-tracking/src/main androidApp/feature-history/src/main` returns nothing, `MainActivity`'s NavHost calls the Root composables, each `<X>Screen` name is declared once, and the "Known deviations" bullet of `tm-android` is removed.
- Refs: `androidApp/feature-route/.../RouteScreen.kt`, `androidApp/feature-tracking/.../TrackingScreen.kt`, `androidApp/feature-history/.../HistoryScreen.kt` and `.../DetailsScreen.kt` (the doc comment "NavHost entry point"); `androidApp/app/.../MainActivity.kt` (`TrailMetricsNavHost`); `tm-android` ("Presentation layer", "Known deviations").

### route-waypoint-marker-ad-hoc-color
- Type: task
- Area: androidApp/feature-route
- Order: 390
- Source: sweep tm-android
- Problem: `tm-android` "Compose": colors come from `core-ui`'s `designsystem/theme`, with no ad-hoc color literals in features (no severity given; read as `important`). The waypoint marker icon in `RouteScreen` is tinted with `Color.Red`, not a theme color (`TrailRed` or `MaterialTheme.colorScheme.error`). Count 1. The other `Color.*` uses are in the theme files themselves and in `core-ui`'s `CurrentLocationMarker` (white border), which is not a feature and was read as not a violation. Recorded, not fixed: this sweep changes no code, and which theme color the marker should use is a design choice.
- Done when: `grep -n 'Color\.Red' androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/RouteScreen.kt` returns nothing and the marker tint is a theme color.
- Refs: `androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/RouteScreen.kt` (the `MarkerComposable` of the waypoints); `androidApp/core-ui/src/main/kotlin/dev/roozbahani/trailmetrics/core/designsystem/theme/Color.kt`; `tm-android` ("Compose").

### route-waypoint-marker-no-content-description
- Type: task
- Area: androidApp/feature-route
- Order: 400
- Source: sweep tm-android
- Problem: `tm-android` "Compose": meaningful `contentDescription` (string resource, `cd_*` key) on interactive or informational elements, `null` only for decorative ones (no severity given; read as `important`). The waypoint marker in `RouteScreen` is a `MarkerComposable` whose `onClick` removes the waypoint, and its `Icon` has `contentDescription = null`. Count 1. The other `null` descriptions were read: they are icons next to a text label, a decorative snapshot image and the bottom bar items, and are decorative. Whether a map marker is reachable by a screen reader at all depends on the Maps Compose version, so the fix needs a decision. Recorded, not fixed.
- Done when: the waypoint marker's `Icon` has a `contentDescription` from a `cd_*` string resource (or the owner records that map markers are exempt in `tm-android`), and `grep -n 'cd_' androidApp/core-ui/src/main/res/values/strings.xml` lists it.
- Refs: `androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/RouteScreen.kt` (`MarkerComposable`); `androidApp/core-ui/src/main/res/values/strings.xml`; `tm-android` ("Compose").

### composables-transform-data-in-composition
- Type: task
- Area: androidApp/feature-route, androidApp/feature-history
- Order: 410
- Source: sweep tm-android
- Problem: `tm-android` "Compose": composables render `state`, with zero business logic and zero data transformation (no severity given; read as `important`). Two composables transform data in composition: `RouteScreen` maps `route.points` to coordinates (`route.points.map { it.coordinates }`) for `RoutePolyline` on every recomposition, and `ActivityRow` in `HistoryScreen` builds a `DateFormat` with `DateFormat.getDateTimeInstance(...)` and formats the start time for every row on every recomposition. Count 2. The second also breaks `tm-robustness` P2 (no allocation in composition; `remember` a derived value), which the stage 1 sweep (#238) did not find. Recorded, not fixed: the fix moves the mapping into the state (`RouteState`) and the date into a display value or a `remember`ed formatter, which changes state classes and tests.
- Done when: `grep -n 'points.map' androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/RouteScreen.kt` returns nothing, `grep -n 'getDateTimeInstance' androidApp/feature-history/src/main/kotlin/dev/roozbahani/trailmetrics/feature/history/HistoryScreen.kt` returns nothing or the formatter is created once per screen, and the existing UI tests pass.
- Refs: `androidApp/feature-route/.../RouteScreen.kt` (`RoutePolyline(points = ...)`); `androidApp/feature-history/.../HistoryScreen.kt` (`ActivityRow`); `tm-android` ("Compose"); `tm-robustness` P2.

### opt-in-without-reason-or-too-wide
- Type: task
- Area: androidApp/feature-route, data
- Order: 420
- Source: sweep tm-android
- Problem: `tm-android` "No deprecated APIs (Kotlin)": opt in as narrowly as possible, at the call expression or the smallest enclosing declaration, with a comment saying why (no severity given; read as `important`; `tm-kmp-shared` applies the Kotlin rules to `data`). Three of five `@OptIn` annotations have no comment: `UserProfileBottomSheet` in `RouteScreen` (`ExperimentalMaterial3Api`), `getDatabaseBuilder` in `DatabaseBuilder.ios.kt` and `IosLocationRepositoryImpl` (both `ExperimentalForeignApi`). The last is on the whole class, wider than the members that use the cinterop API. Count 3 (one of them also too wide). The `MapEffect` opt-in in `TrackingScreen` and the one in `SystemClock.ios.kt` give their reason and are narrow. Recorded, not fixed: this sweep changes no code.
- Done when: every `@OptIn` in production Kotlin has a comment line saying why, and `IosLocationRepositoryImpl` opts in on the members that need it; `grep -rn -B1 '@OptIn' androidApp data --include=*.kt` shows a comment above each.
- Refs: `androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/RouteScreen.kt` (`UserProfileBottomSheet`); `data/src/iosMain/kotlin/dev/roozbahani/trailmetrics/data/local/database/DatabaseBuilder.ios.kt`; `data/src/iosMain/kotlin/dev/roozbahani/trailmetrics/data/location/IosLocationRepositoryImpl.kt`; `tm-android` ("No deprecated APIs (Kotlin)").

### unused-template-colors-in-core-ui
- Type: task
- Area: androidApp/core-ui
- Order: 430
- Source: sweep tm-android
- Problem: `tm-android` "No dead code": unused `internal`/`public` code is not caught by detekt, so check it yourself (no severity given; read as `important`). `core-ui`'s `Color.kt` keeps six default-template colors (`Purple80`, `PurpleGrey80`, `Pink80`, `Purple40`, `PurpleGrey40`, `Pink40`) under "Default template colors". `git grep` finds each name only in its own declaration, so none is used by any module, test or resource. Count 6, one file. Recorded, not fixed: this sweep changes no code (and `UnusedPrivateProperty` would not flag a public `val`).
- Done when: `git grep -n -E 'Purple80|PurpleGrey80|Pink80|Purple40|PurpleGrey40|Pink40' -- . ':!BOARD.md'` returns nothing and the "Default template colors" comment is gone.
- Refs: `androidApp/core-ui/src/main/kotlin/dev/roozbahani/trailmetrics/core/designsystem/theme/Color.kt`; `tm-android` ("No dead code").

### ios-tracking-viewmodel-switch-default-on-kotlin-enum
- Type: task
- Area: iosApp/Tracking
- Order: 460
- Source: sweep tm-ios
- Problem: `tm-ios` "SKIE interop": keep the `switch onEnum(of: value)` exhaustive so a new Kotlin case breaks the Swift build (no severity given; read as `important`). In `TrackingViewModel`, `currentPath` switches on `onEnum(of: trackingState)` and ends in `default:`, so a new `TrackingState` case would compile and silently fall into the default (empty path). `canStop` had the same shape and now asks `domain`'s `availableControls`. Count 1, one file (`currentMetrics` lists every case since PR restore-fixes). The other switches on `onEnum(of:)` (`ContentView`, `HistoryViewModel`, `RouteUiError+Message`, `onStopClicked`) list every case. Recorded, not fixed: this sweep changes no code.
- Done when: `grep -n 'default:' iosApp/Packages/Tracking/Sources/Tracking/TrackingViewModel.swift` returns nothing and `currentPath` lists all `TrackingState` cases (or is replaced by the shared domain rule).
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/TrackingViewModel.swift` (`currentPath`); `tm-ios` ("SKIE interop from Swift").

### ios-contentview-calls-koinhelper
- Type: task
- Area: iosApp
- Order: 470
- Source: sweep tm-ios
- Problem: `tm-ios` "Koin / KoinHelper" and "ViewModel shape": never call `KoinHelper()` anywhere except in a default argument or the composition root (no severity given; read as `important`). `ContentView.handleOpenURL` calls `KoinHelper().trackingSessionManager().currentState.value` and switches on it to decide whether to select the Route tab. `ContentView` is a View, not the composition root (`TrailMetricsApp.init`), so the read bypasses injection and no test can fake it. Count 1. Recorded, not fixed: the fix (the app-level state or a small ViewModel for the tab selection, injected with a default parameter) is a design choice for the app target.
- Done when: `grep -n 'KoinHelper()' iosApp/TrailMetrics/ContentView.swift` returns nothing and the open-URL handling reads the session state through an injected dependency, with a test or a UI-test scenario for the tab switch.
- Refs: `iosApp/TrailMetrics/ContentView.swift` (`handleOpenURL`); `iosApp/TrailMetrics/TrailMetricsApp.swift`; `tm-ios` ("Koin / KoinHelper").

### ios-viewmodel-state-not-private-set
- Type: task
- Area: iosApp/Route, iosApp/History
- Order: 480
- Source: sweep tm-ios
- Problem: `tm-ios` "ViewModel shape": use `public private(set)` for state the View must not write (no severity given; read as `important`). Ten `@Published public var` properties are never written by a View (`grep` finds no `viewModel.<name> =` and no `$viewModel` binding anywhere): `RouteViewModel` `startPoint`, `waypoints`, `generatedRoute`, `userProfile`, `selectedActivityType`, `isLoading`; `HistoryViewModel` `activities`, `isLoading`; `DetailsViewModel` `activity`, `isLoading`. Count 10 in 3 files. `TrackingViewModel` and the two `errorMessage` properties already use `private(set)`. The skill's own ViewModel example also shows `@Published public var activities` and `isLoading`, so the example must change with the code. Recorded, not fixed: this sweep changes no code; package tests that assign the properties would need the setter back or a different seam.
- Done when: `grep -rn '@Published public var' iosApp/Packages/*/Sources` returns nothing, the package tests pass, and the example in `tm-ios` ("ViewModel shape") shows `public private(set)`.
- Refs: `iosApp/Packages/Route/Sources/Route/RouteViewModel.swift`; `iosApp/Packages/History/Sources/History/HistoryViewModel.swift`, `.../DetailsViewModel.swift`; `tm-ios` ("ViewModel shape").

### ios-design-system-unused-colors
- Type: task
- Area: iosApp/DesignSystem
- Order: 490
- Source: sweep tm-ios
- Problem: `tm-ios` "No dead code": no unused declarations (`tm-android`, "No dead code", which it refers to, notes that unused public code is not caught by a linter). `Color+TrailMetrics.swift` in `DesignSystem` declares `trailGreenLight`, `trailBlue` and `trailBlueLight`; `git grep` finds each name only in its own declaration, so no package, target or test uses them (`trailGreen`, `trailRed` and `trailAmber` are used). Count 3, one file. They mirror Android's brand colors and may be wanted for the Figma design system epic, so whether to delete or keep them is a decision. Recorded, not fixed.
- Done when: `git grep -n -E 'trailGreenLight|trailBlueLight|trailBlue\b' -- iosApp` returns nothing, or each is used by a view, or the owner records that the tokens are kept for the design system.
- Refs: `iosApp/Packages/DesignSystem/Sources/DesignSystem/Color+TrailMetrics.swift`; `tm-ios` ("No dead code"); `figma-design-system`.

### pause-resume-joins-path-with-a-straight-segment
- Type: task
- Area: domain, androidApp, iosApp
- Order: 540
- Source: PR persist-tracking-restore-ios
- Problem: The owner saw, on an Android device, that after Pause and Resume the recorded line joins the last point before the Pause to the first point after the Resume with a straight segment (a chord across a circle). The jump is no longer counted as distance (the first location after a Resume adds none, `TrackingMetrics.awaitingFirstFixAfterResume` in `UpdateTrackingStateUseCase`), but the line is still drawn: the path is a plain `List<Coordinates>`, so it has no gap marker and the Pause leaves no trace in it. Android draws the whole path as one `Polyline` (`RoutePolyline` in `TrackingScreen`), and iOS draws it as one `GMSPolyline` (`TrackingMapView`, `recordedPathToDraw`), so both show the chord; the saved activity keeps the same list. A restored session adds one more such chord (it comes back Paused, and its Resume continues from the last stored point). Not changed here: whether a pause splits the line is a product decision with a model change in `domain`, both maps and the stored form (a Room schema change for the saved activity and the stored session).
- Done when: a pause splits the polyline so no straight chord is drawn on either map, also in the saved history, as the owner decides.
- Refs: `domain/.../usecase/UpdateTrackingStateUseCase.kt` (`handleResume`, `handleLocationReceived`); `androidApp/core-ui/.../map/RoutePolyline.kt`; `androidApp/feature-tracking/.../TrackingScreen.kt`; `iosApp/Packages/Tracking/Sources/Tracking/TrackingMapView.swift`; `domain/.../model/TrackingMetrics.kt` (`path`).

### rule-change-signal-misses-escalation-words
- Type: task
- Area: scripts, tm-pr-review
- Order: 570
- Source: PR koinhelper-getter-no-escalation
- Problem: `scripts/check-skill-rule-changes.py` (`tm-pr-review` item 10) lists a removed or rewritten skill line only when it holds one of its `RULE_WORDS` (must, never, always, do not, don't, required, forbidden, only, at most, at least). A rule written as "... stay an escalation", "is blocking" or "escalates" holds none, so weakening it is not listed: rewriting the last clause of `tm-kmp-shared` rule 6 ("... and any change to `KoinHelper` stay an escalation") gave `none` on this PR, although it is a rule weakening. Recorded, not fixed: of another subject (the review tooling), the script is a protected path, and which words count as rule words is the owner's decision.
- Done when: the script lists a removed or rewritten line whose rule is written with escalate/escalation or blocking (or the owner decides such lines are left to the reviewer, written in `tm-pr-review` item 10), with a `--self-test` case for it.
- Refs: `scripts/check-skill-rule-changes.py` (`RULE_WORDS`); `.claude/skills/tm-pr-review/SKILL.md` (item 10); `.claude/skills/tm-kmp-shared/SKILL.md` ("`@Throws` policy", rule 6).

### widget-catalog-keys-go-stale-on-build
- Type: task
- Area: iosApp/TrackingWidget
- Order: 580
- Source: task 61b stage 1 (owner's report request)
- Problem: An Xcode build of the app rewrites `iosApp/TrackingWidget/Localizable.xcstrings`: it adds `"extractionState" : "stale"` and drops the final newline. Cause: with `SWIFT_EMIT_LOC_STRINGS = YES` (the widget target) the compiler extracts each target's string literals into `.stringsdata`, and Xcode's String Catalog sync marks every catalog key that no target extracted as `stale`, then writes the file with its own serializer (no final newline). Three widget keys, `Cycling`, `Running` and `Walking`, are never extracted: the widget shows them as `Text(LocalizedStringKey(context.attributes.activityType), bundle: .main)`, a runtime string. Measured on Xcode 27.1 with the gate's command line (`xcodebuild build -scheme TrailMetrics`, simulator): 7 of the 10 widget keys are extracted, every key of the app and of the three package catalogs is, and the command-line build changed no catalog. The rewrite therefore comes from a build in the Xcode app, whose catalog sync runs after the build; that build was not run here. Recorded, not fixed: report-only by the owner's task; the owner chooses the change.
- Done when: the owner has chosen, and a build in Xcode leaves every catalog unchanged. Smallest change found: give the three keys `"extractionState" : "manual"` in the widget catalog (the state Xcode gives a key added by hand, which it never marks stale); no build setting or code changes. Alternatives: make the keys literals the compiler extracts (a `switch` over the activity type returning `Text("Running", bundle: .main)` and so on: a code change), or a gate check that fails on `"stale"` or a missing final newline in a catalog (it detects the rewrite, it does not stop it). Turning `SWIFT_EMIT_LOC_STRINGS` off for the widget target would leave every widget key unextracted, which is worse.
- Refs: `iosApp/TrackingWidget/Localizable.xcstrings`; `iosApp/TrackingWidget/TrackingLiveActivity.swift` (`LocalizedStringKey(context.attributes.activityType)`); `iosApp/TrailMetrics.xcodeproj/project.pbxproj` (`SWIFT_EMIT_LOC_STRINGS`, `LOCALIZATION_PREFERS_STRING_CATALOGS`); `.claude/skills/tm-ios/strings-and-accessibility.md` ("Strings").

### scripts-folder-moves
- Type: task
- Area: scripts, .github/workflows/ci.yml, .github/CODEOWNERS, skills
- Order: 590
- Source: task 61b stage 3 (PR chore/self-test-list-and-pr-base)
- Problem: Stage 3 of task 61b groups the flat `scripts/` entries into folders by purpose. The first PR made the folders `scripts/checks/` and `scripts/ci/` (the self-test list and its runner, the scripts index, the PR-base script), `scripts/README.md` and its check; the existing scripts still sit flat in `scripts/`. Moving them changes about 360 references outside `scripts/` (skills, `CLAUDE.md`, `ci.yml`, `CODEOWNERS`, docs, the gate and the hooks), too many for one reviewable PR. Recorded, not fixed: over the sweep's bound; the owner reviews and pushes each folder's PR (`ci.yml` changes).
- Done when: one PR per folder, each moving its scripts with their `*-fixtures/` folders and fixing every reference, with `scripts/README.md`, `scripts/checks/self-tests.list` and `CODEOWNERS` (a folder line in place of the per-script lines) updated and `check-protected-paths.sh --validate` passing: (1) `checks/`: `classify-changes` and every `check-*` (`.sh`, `.py`, fixtures); (2) `review/`: `review-task`, `local-review-gate`, `skill-changes-digest`, `set-pr-body`; (3) `ci/`: `wait-for-checks`, `read-ci-verdict`, `rerun-failed-once`, `main-ci-status`; (4) `dev/`: `filter-xcode-log`, `scrub-env`, `prune-merged-branches`, `simulate-route` with `routes/`. `pre-push-check.sh`, `build-kmp-framework.sh` and `claude-hooks/` stay where they are: `CLAUDE.md` and every skill name the gate; the Xcode project, its schemes and the Gradle and Kotlin sources name the framework build; `.claude/settings.json` names the hooks, and only the owner edits it.
- Refs: `scripts/README.md`; `scripts/checks/self-tests.list`; `.github/CODEOWNERS`; `.github/workflows/ci.yml`; `.claude/settings.json`.

### ui-test-app-idle-stalls
- Type: task
- Area: iosApp/TrailMetricsUITests, shared-uitest, the screens under test
- Order: 610
- Source: chat 2026-11-13 (owner, after the flake-log analysis of the three failures)
- Problem: Needs the owner's decision and a design (what the UI-test variant may change). Three failures of `iOS 3 — run UI tests` on two signatures (`ios-ui-details-failed-delete-error-alert-not-shown` twice, `ios-ui-restored-session-offer-not-offered` once; runs 43318989709, 43431312123, 43451417675) took 84 to 87 s on different tests, and each holds one long stall inside XCTest's own "Wait for the app to idle" step (49 s; 18 s plus 33 s; exactly 60.0 s) before the test's last 10 s wait. Every wait in the UI tests is 10 s and the CI step sets no per-test allowance, so no wait or timeout explains it; the same tests pass in about 10 to 28 s. What keeps the app busy in these screens is not shown: candidates are map rendering (the Maps view), timers (the tracking clock, the probe refresh), animations, and progress views or spinners (Generate, delete in progress), or only a loaded runner. A fourth failure (run 43471164004, the entry `ios-ui-probe-refresh-timeout`, second occurrence) stalled 77.7 s in XCTest's "Wait for com.apple.springboard to idle", the simulator's SpringBoard and not our app, so the investigation covers the app and the simulator or runner. The owner's constraint: no retries and no longer waits.
- Done when: the cause is shown for the Details-after-delete and the restored-session Tracking screens (which element, timer or animation keeps the app busy, from a CI run's recorded UI hierarchy or a sample of the app), the owner has decided whether the UI-test variant (`shared-uitest`, the launch-time seam) can avoid it, for example by disabling animations or stopping a ticking timer in the test variant, and the change is made so that the iOS UI suite shows no idle stall of 18 s or more on 5 consecutive local runs (the gate's iOS UI tests step or the full run on `main`, `scripts/main-ui-run.sh`; the CI job `iOS 3` was removed). No retry and no longer wait is added. For the SpringBoard stall the cause is shown too (the simulator's state, the runner's load or the simulator settings), and the owner has decided what the local runner script (`scripts/ios-ui-tests.sh`) or the simulator settings may change.
- Refs: `CI_FLAKES.md` (the entries `ios-ui-details-failed-delete-error-alert-not-shown`, `ios-ui-restored-session-offer-not-offered` and `ios-ui-probe-refresh-timeout`); `iosApp/TrailMetricsUITests/DetailsFailedDeleteUITests.swift`; `iosApp/TrailMetricsUITests/Tracking/RestoredSessionOfferUITests.swift`; `iosApp/TrailMetricsUITests/Support/UITestProbe.swift`; `shared-uitest`.

### ios-history-row-snapshot-image-ui-test
- Type: task
- Area: iosApp/TrailMetricsUITests, shared-uitest, iosApp/Packages/History
- Order: 620
- Source: PR #290 (CI reviewer, Tier 2 reason 2), 2026-11-14
- Problem: Needs the owner's decision and a design (what the UI-test variant may seed). No automated test observes the map snapshot image of a History row: `HistoryViewModelTests` cover `snapshotURL(for:)`, but `ActivityRow` draws it with `AsyncImage`, and the UI-test seam's `FakeActivityHistoryRepository` emits a fixed list whose records carry no snapshot file, so a UI test cannot show or miss an image. The behavior (a stored path of an old container still shows its image) is checked by hand after a reinstall until then.
- Done when: the owner has decided whether the UI-test variant seeds a snapshot file for a History record, and a `TrailMetricsUITests` scenario shows the row's image (an element that exists only when the image loaded, for example an accessibility identifier on the loaded image) and fails when the stored path no longer resolves, shown on a deliberately broken version.
- Refs: `iosApp/Packages/History/Sources/History/HistoryView.swift` (`ActivityRow`); `iosApp/Packages/History/Sources/History/HistoryViewModel.swift` (`snapshotURL(for:)`); `shared-uitest`; `docs/epics/ios-ui-tests.md`; `.claude/skills/tm-testing` ("XCUITest").

### android-first-minified-release-build
- Type: task
- Area: androidApp/app, config, CI
- Order: 630
- Source: spike android/skills 2026-11-15
- Problem: Needs the owner's decision and design, and part of it is a workflow file change (the owner merges it). A minified release build of the Android app has never been built or run. In `androidApp/app/build.gradle.kts` the `release` build type has `optimization { enable = false }` (R8 off), there are no keep rules and no `proguardFiles`, and CI builds `assembleDebug` only. `versionCode = 1` and `versionName = "1.0"` are hard-coded, there is no signing config and no `bundleRelease`, and nothing says who produces the AAB or where the keystore lives. The first minified build will probably break something that Robolectric cannot show, because its tests run unminified classes: type-safe navigation (`typeOf`, reflection), kotlinx-serialization, Ktor, Koin, Room 3 (`androidx.room3`), Maps and Coil 2. AGP 9 changed the R8 defaults, which apply from the day R8 is on: `android.r8.strictFullModeForKeepRules` is true (a keep rule no longer keeps the default constructor implicitly), `android.r8.optimizedResourceShrinking` is true, `android.r8.proguardAndroidTxt.disallowed` is true (only `proguard-android-optimize.txt`), `android.r8.globalOptionsInConsumerRules.disallowed` is true (no global option such as `-dontobfuscate` in a library's consumer rules), and `android.proguard.failOnMissingFiles` is true. In the KMP library modules (`data` above all: Room, Ktor, serialization) consumer keep rules do not use `consumerProguardFiles`: in AGP 9.2.1 that exists only on the classic library DSL, and the KMP target has `kotlin { android { optimization { consumerKeepRules } } }` (`KmpOptimization.consumerKeepRules`, a `ConsumerKeepRules` with `publish`, `ignoreFrom` and `ignoreFromAllExternalDependencies`; checked with `javap` on `gradle-api-9.2.1.jar`, not compiled). The Maps API key (read from `local.properties` into the `MAPS_API_KEY` manifest placeholder) ships in the manifest; its protection is a restriction by package name and signing certificate in Google Cloud Console, which nothing in the repository records.
- Done when: R8 is on in `release` with the smallest keep rules the build needs (each with a comment saying what it protects); versioning and signing are decided and written down (who builds the AAB, where the keystore lives, how `versionCode` grows); CI builds a release variant (a workflow change, a PR the owner merges); one human runs the minified build on a device through every screen (Route with the map, Tracking with a started and finished session, History, Details) and reports the result; and the Play App Signing certificate's SHA-1 is added to the Maps key's restriction next to the package name.
- Refs: `androidApp/app/build.gradle.kts`; `.github/workflows/ci.yml`; `androidApp/app/src/main/AndroidManifest.xml` (`MAPS_API_KEY`); `tm-pr-workflow` (Tier 2).

### android-backup-and-data-extraction-rules
- Type: task
- Area: androidApp/app
- Order: 640
- Source: spike android/skills 2026-11-15
- Problem: Needs an owner decision on what may leave the device. `AndroidManifest.xml` has `allowBackup="true"` and points at `@xml/data_extraction_rules` and `@xml/backup_rules`, which are still the unedited sample templates, so the Room database of recorded GPS tracks and the saved map snapshot files go into cloud backup and device-to-device transfer. That is probably wrong for location history (privacy, the Play data safety answers), and a restored database lands on a device where the stored tracking session and the service state do not match.
- Done when: the owner has decided what is backed up and transferred (nothing, the database without the snapshots, or all), `data_extraction_rules.xml` and `backup_rules.xml` say so with explicit include and exclude entries (or `allowBackup` is `false`), and the data safety answers of `android-play-release-checklist` use the decision.
- Refs: `androidApp/app/src/main/AndroidManifest.xml`; `androidApp/app/src/main/res/xml/data_extraction_rules.xml`, `backup_rules.xml`.

### android-location-permission-denial-and-disclosure
- Type: task
- Area: androidApp/feature-route, androidApp/feature-tracking, androidApp/core-ui
- Order: 650
- Source: spike android/skills 2026-11-15
- Problem: Needs the owner's design (product copy, a prominent disclosure, where the user is sent). The location permission flow has only the granted path: the launchers in `RouteScreen.kt` and `TrackingScreen.kt` request fine and coarse location together, send `LocationPermissionGranted` when either is granted and do nothing otherwise. There is no rationale and no way to the app's settings after the user has refused permanently, so a user who tapped "Don't allow" twice sees only the `MissingLocationPermission` error and cannot recover in the app. The notification permission is asked with `LaunchedEffect(Unit)` on every entry to the tracking screen with an empty result callback; a denied notification hides the foreground notification (and its Stop) and the app does not say so. No prominent disclosure explains the location use before the system dialog, which Play's location policy requires.
- Done when: the three outcomes for location (granted, rationale needed, permanently denied with a way to the app's settings) are handled and the notification denial is explained; a disclosure text before the first request exists, in the owner's words; each outcome has a ViewModel or Compose test; the permission state is never cached (checked at the use site).
- Refs: `androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/RouteScreen.kt`; `androidApp/feature-tracking/src/main/kotlin/dev/roozbahani/trailmetrics/feature/tracking/TrackingScreen.kt`; `RouteViewModel` (`MissingLocationPermission`); `AndroidLocationRepositoryImpl` (`SecurityException` mapping).

### android-crash-and-anr-reporting
- Type: task
- Area: androidApp/app, release (Firebase console, a device)
- Order: 660
- Source: spike android/skills 2026-11-15; owner decision 2026-11-25 (Firebase Crashlytics, free plan, no Analytics)
- Problem: Needs the owner's Firebase project and a device; the agent has neither. The app module reports crashes, ANRs and non-fatals with Firebase Crashlytics (BoM 35.2.0), but only when `androidApp/app/google-services.json` (git-ignored) is present; without it nothing is reported. No test can show that a report reaches the console.
- Done when: the owner has put the Firebase project's `google-services.json` in `androidApp/app/`, uninstalled the app (`adb uninstall dev.roozbahani.trailmetrics`, so no crash stored by an earlier debug build is sent), installed a debug build built with `-Ptrailmetrics.crashReportingInDebug=true` on a device (a debug build does not report without it, owner decision 2026-11-25; the property is given on the command line or in the user's own `~/.gradle/gradle.properties`, never committed), and seen in the Crashlytics console both a crash from `adb shell am broadcast -a dev.roozbahani.trailmetrics.CRASH_REPORTING_CHECK --es kind crash` with a readable stack (`CrashReportingCheckException` in `CrashReportingCheckReceiver.onReceive`) and an ANR with the main thread's stack from a local, uncommitted build in which `CrashReportingCheckReceiver.onReceive`'s `when` has one more branch, `"anr" -> Thread.sleep(30_000L)` (the agent also left it as `~/agent-workspace/keep-crashlytics-anr-check.patch`), then `adb shell am broadcast --receiver-foreground -a dev.roozbahani.trailmetrics.CRASH_REPORTING_CHECK --es kind anr` and taps on the screen; reopen the app so the report is sent; a committed ANR trigger would break `tm-robustness` C1 and C5); the data safety answers of `android-play-release-checklist` include the Crashlytics rows.
- Refs: `androidApp/app/build.gradle.kts` (`googleServices`); `androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/CrashReportingCheck.kt`; `android-play-release-checklist`; Firebase's Play data disclosure page.

### crash-reporting-no-analytics-check
- Type: task
- Area: scripts, CI, gate
- Order: 665
- Source: CI review of #377 ([important] item 7), local review of #376 (note 4); 2026-11-25
- Problem: Needs the owner: the agent's wiring of this check into `scripts/pre-push-check.sh`, `.github/workflows/ci.yml`, `.github/CODEOWNERS`, `scripts/checks/self-tests-tooling.list` and `scripts/README.md` was refused by the permission classifier ("[Undermining Oversight]") on 2026-11-25. Crashlytics is used without Analytics and without the advertising ID, but nothing keeps it so: `Package.resolved` pins `googleappmeasurement` and `google-ads-on-device-conversion-ios-sdk` because firebase-ios-sdk declares them, and a BoM or product change on Android could merge the AD_ID permission or measurement components. Today neither app has any (checked on the built apps). The script is written and its self-test passes (10 cases); it is kept outside the repository at `~/agent-workspace/keep-check-no-analytics-linked.sh`.
- Done when: `scripts/check-no-analytics-linked.sh` (`--android` on the merged manifest after `assembleDebug`, `--ios` on the built app after the iOS build, `--self-test`) is in the repository and runs in the gate and in CI's android-build and ios-build jobs, with its self-test in the `tooling` list, an index line and a CODEOWNERS line; or the owner decides against the check.
- Refs: `iosApp/TrailMetrics.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`; `androidApp/app/build.gradle.kts`; `tm-agent-loop` (`denied-commands.md`).

### android-play-release-checklist
- Type: task
- Area: release (Play Console, not code)
- Order: 670
- Source: spike android/skills 2026-11-15
- Problem: Needs the owner's decisions and answers (declarations, disclosure text and data safety answers are the owner's to give); the steps are done in Play Console and in writing, and nothing in the repository records them. Before the first Play submission: the foreground-service declaration for the `location` type (a functional description and a video of the user impact; required for apps targeting Android 14 and later, and the app targets 37); the prominent disclosure text before the location request (`android-location-permission-denial-and-disclosure`); the data safety form (GPS tracks stored locally, requests to a directions API; the decision of `android-backup-and-data-extraction-rules` changes the answers; Firebase Crashlytics, owner decision 2026-11-25, adds these rows, mapped by the agent from Firebase's Play data disclosure, which names no Play data types: App info and performance > Crash logs (stack traces, exception class and message, app state at the crash) and > Diagnostics (device model, OS, RAM, disk, rooted flag), Device or other IDs (the Crashlytics installation UUID and the Firebase installation ID, per installation, not a device or user identifier), each collected automatically, not shared (Firebase processes it for the developer), encrypted in transit, purpose Analytics (crash diagnosis), kept 90 days; no advertising ID, no location in reports); a privacy policy URL; content rating, target audience and an internal testing track; the target SDK deadline. Google's `play-policy-insights` skill sends the package name to play.google.com, so the agent does not run it; its location and foreground-service tables are a usable checklist.
- Done when: each item above is done or answered, with the declaration text, the video and the policy URL kept where the owner decides, and the first internal-testing release is accepted.
- Refs: `androidApp/app/src/main/AndroidManifest.xml` (`foregroundServiceType="location"`); `android-first-minified-release-build`.

### android-tracking-service-restart-and-battery-killing
- Type: task
- Area: data (TrackingService), androidApp
- Order: 680
- Source: spike android/skills 2026-11-15
- Problem: Needs the owner's product decision, and a device to show the facts it rests on (the agent has no device and no test can show them). (1) `TrackingService` returns `START_STICKY` and restores the stored session when the system restarts it after the process was killed (`onStartCommand` with a null intent, `handleRestart`; `tm-robustness` R2 promises a restore or a notice). It is not known whether a system-initiated restart of a location foreground service from the background can still read location on Android 12 and later without background location permission, so the restored session may be restored but receive no updates. (2) Doze and vendor background killers (the usual field complaint of trackers: "my run stopped") are not handled: nothing asks the user to exempt the app and nothing detects an unexpected stop. Also `startForeground(NOTIFICATION_ID, notification)` is called without the service-type argument; whether the three-argument form is required at target 37 is unverified.
- Done when: someone ran on a device (start tracking, `adb shell am kill dev.roozbahani.trailmetrics`, watch whether the service comes back and whether location updates arrive), the result is written down, and the owner decided what the app does about it (a code fix, a notice, or the accepted limit); the same for one battery-optimised device; the `startForeground` form is checked against the documentation for target 37.
- Refs: `data/src/androidMain/kotlin/dev/roozbahani/trailmetrics/data/tracking/TrackingService.kt`, `RestartAction.kt` (`handleRestart`); `tm-robustness` R2.

### android-baseline-profiles-and-macrobenchmark
- Type: task
- Area: androidApp/app, build
- Order: 690
- After: android-first-minified-release-build
- Source: spike android/skills 2026-11-15
- Problem: Needs the owner's decision (new dependencies: `androidx.profileinstaller`, a baseline-profile plugin, `androidx.benchmark`) and a device or emulator to generate and measure. The app has no Baseline Profile and no Macrobenchmark (no `baselineprofile`, `benchmark` or `profileinstaller` anywhere). Startup of a Compose, Koin, Room and Maps app is the cost a profile removes, and a performance claim needs a measurement on a release build, which does not exist yet.
- Done when: the owner approved the dependencies, a baseline profile is generated and shipped in the release build, and a Macrobenchmark of cold start exists with its result recorded.
- Refs: `androidApp/app/build.gradle.kts`; `gradle/libs.versions.toml`; `android-first-minified-release-build`.

### android-predictive-back
- Type: task
- Area: androidApp/app, androidApp/feature-tracking
- Order: 700
- Source: spike android/skills 2026-11-15
- Problem: Needs the owner's decision (polish, and a possible new dependency). The manifest does not set `android:enableOnBackInvokedCallback`, so the system default applies: predictive back is on for API 36 and later at target 37 and not on API 33 to 35. The only back handling is `BackHandler(enabled = hasActiveSession)` in `TrackingScreen.kt`, which confirms before leaving an active session. `androidx.navigationevent`'s `NavigationBackHandler` would add the back-gesture progress for an animation; it is a new dependency.
- Done when: the owner decided whether predictive back is wanted below API 36 (the manifest attribute set to `true`) and whether the tracking confirmation moves to `NavigationBackHandler`, and the decision is implemented or this record is deleted as declined.
- Refs: `androidApp/app/src/main/AndroidManifest.xml`; `androidApp/feature-tracking/src/main/kotlin/dev/roozbahani/trailmetrics/feature/tracking/TrackingScreen.kt` (`BackHandler`).

### android-production-gaps-unassigned
- Type: task
- Area: androidApp, config, CI
- Order: 710
- Source: spike android/skills 2026-11-15
- Problem: Needs the owner to pick which of these to do; each is a decision, none is a defect the agent can fix alone. The Android app lacks, with no recorded decision: (1) localization: one `strings.xml` per module, no `values-xx`, no `localeConfig`, and the tracking notification's text and channel name are hard-coded English in `TrackingService` (see `android-tracking-notification-content`); unit words and number formats are shared code (`shared-metrics-formatter-user-visible-strings` and `ios-hardcoded-number-formatting` cover shared and iOS); (2) accessibility beyond the `cd_*` content descriptions: no TalkBack pass, no font-scale test, touch targets, live regions for the changing numbers, contrast; (3) a network security configuration and a written cleartext and pinning choice for the directions API; (4) a release logging policy: `AndroidLogger` calls `Log.d` for everything and `MapSnapshotSaver` logs exceptions with `Log.e`, and whether coordinates reach a log was not checked; (5) dependency vulnerability and license scanning and an update flow for Gradle, SPM (`ios-maps-sdk` and the other package dependencies) and GitHub Actions (no Dependabot or Renovate, no scan step in CI). A Kotlin bump moves a lockstep group together: Kotlin, SKIE (each release supports specific Kotlin versions), the Compose compiler plugin (its version is the Kotlin version), KSP and Room's KSP processor; (6) lint as a release gate: no `lint-baseline.xml` or severity policy seen; (7) instrumented tests on a device in CI: none by design, so the real foreground service, permission dialogs and Maps are covered only by human checks, and no process-death or startup test exists (`tm-robustness` R1); (8) in-app updates, review prompts, remote config or a kill switch; (9) scheduled background work, needed only when a sync feature exists. (10) large screens and foldables: no `WindowSizeClass` or adaptive layout, and a phone layout is what a tablet or an unfolded device shows at target 37; (11) deep links: `AppRoute` has none, and nothing says how an intent that opens a destination, or a restored back stack that holds the tracking destination, behaves.
- Done when: the owner has gone through the list and, for each item, made it a record of its own (a PR narrows this record to the remaining items) or declined it; this record is then deleted.
- Refs: `androidApp/*/src/main/res/values/strings.xml`; `data/src/androidMain/kotlin/dev/roozbahani/trailmetrics/data/common/AndroidLogger.kt`; `androidApp/feature-tracking/src/main/kotlin/dev/roozbahani/trailmetrics/feature/tracking/util/MapSnapshotSaver.kt`; `.github/workflows/ci.yml`; `tm-robustness` R1.

### flake-android-package-debug-incremental-failure
- Type: task
- Area: CI (`.github/workflows/ci.yml`), androidApp/app
- Order: 720
- Source: CI run 43707938041 (main, push, head 31b71dd, the merge of #296), 2026-11-15; escalated at count 3 from the entry `android-package-debug-incremental-failure` in `CI_FLAKES.md`
- Problem: Needs the owner: capturing the cause needs a change to the job in `.github/workflows/ci.yml`, a workflow file (the owner merges that PR). `Android build — lint, Detekt, tests, coverage, debug build, Room export` failed three times on `main` in `Build` at `:androidApp:app:packageDebug` with "A failure occurred while executing com.android.build.gradle.tasks.PackageAndroidArtifact$IncrementalSplitterRunnable" and no cause line: run 39606497367 (2026-10-21, head 90a0f7d), run 42835745551 (2026-11-10, the merge of #246, head 79fb11b) and run 43707938041 (2026-11-15, the merge of #296, head 31b71dd; failed after 21 s). None was re-run. The first two merges changed no `androidApp/app` source; the third did (`MainActivity.kt`, plus `data` sources), and the PR's own run of the same tree was green, so whether all three share one cause is not shown by the identical first line. Class `infra` (runner, restored Gradle cache or the incremental packaging state) is a hypothesis, not a finding. The log of every run ends at that line because the build ran without `--stacktrace` or `--info`.
- Done when: the next occurrence is captured with its cause (the failing task's `--stacktrace` and `--info` output, whether the Gradle cache was restored and from which key, the state of `androidApp/app/build` before `packageDebug`, and the runner image), the cause is named, and then the flake no longer fails, or the step is changed so it cannot, shown on 5 consecutive runs of the job on `main`. If it never recurs, the owner closes the record.
- Refs: CI runs 39606497367, 42835745551 and 43707938041; `CI_FLAKES.md` (`android-package-debug-incremental-failure`); `.github/workflows/ci.yml` (the `./gradlew assembleDebug` step and `Setup Gradle`).

### release-step-calls-main-ui-run
- Type: task
- Area: scripts, release
- Order: 910
- Source: owner queue of 2026-11-15, step 3
- Problem: Needs the owner's decision and design: nothing in this repository releases yet (no tag, signing or store-build step; see `android-first-minified-release-build` and `release-build-links-debug-xcframework`), so nothing calls `scripts/main-ui-run.sh --release`, which exits 0 only when the full UI run of the current `main` is green (it runs that run first when it is due). Low priority.
- Done when: a release step exists and its first action is `scripts/main-ui-run.sh --release`; the step stops when that exits non-zero, and a test or self-test of the step shows it.
- Refs: `scripts/main-ui-run.sh`; `.claude/skills/tm-agent-loop/SKILL.md` (section 9).

## Drift

### data-kover-comment-stale-figure
- Type: drift
- Area: data
- Order: 230
- Source: PR for location-current-swallows-cancellation
- Problem: The comment above the Kover floor in `data/build.gradle.kts` gives the measured coverage as 44.38% (142/320 lines). With `AndroidLocationRepositoryImplTest` the `data` host report measures 49.38% (160 of 324 lines) and the floor in `config/kover-floors.properties` is 48. `data/build.gradle.kts` is a protected path, so the comment was left as it is.
- Done when: the comment states the current measured figure, or no longer quotes one, in a PR that may touch the protected path.
- Refs: `data/build.gradle.kts` (Kover floor comment); `config/kover-floors.properties`.

### ownerless-folders-markdown-only-comments
- Type: drift
- Area: .claude
- Order: 232
- Source: PR for pr-review-item-3-reference-skill-files
- Problem: `scripts/check-protected-paths.py` now protects a file in the five ownerless skill folders whose name does not end in `.md`, but two lines still say every file there is open: the comment above the five ownerless lines in `.github/CODEOWNERS` ("an agent may edit them and add files to them") and the "Boundaries" paragraph in `.claude/skills/tm-pr-workflow/SKILL.md` ("every file in them is open"). Both are protected paths outside this PR's authorization.
- Done when: both say that Markdown files in those folders are open and any other file is protected, in a PR that may touch the protected paths.
- Refs: `.github/CODEOWNERS` (reference skills comment); `.claude/skills/tm-pr-workflow/SKILL.md` ("Boundaries"); `scripts/check-protected-paths.py` (`protecting_pattern`).

### skill-lists-omit-new-skills
- Type: drift
- Area: docs
- Order: 243
- Source: PR for tm-robustness-skill
- Problem: Two lists of the skills do not name them all. `README.md` ("`.claude/skills/`") and `docs/architecture/OVERVIEW.md` ("`.claude/skills/`") list `tm-kmp-shared`, `tm-android`, `tm-ios`, `tm-testing`, `tm-pr-workflow` and `epic-orchestration`, and omit `tm-agent-loop`, `tm-pr-review` and `tm-robustness`. `docs/architecture/` is protected and outside this PR's authorization, and the omission of the first two predates it.
- Done when: both lists name every skill folder under `.claude/skills/`, in a PR that may touch `docs/architecture/`.
- Refs: `README.md` (documentation list); `docs/architecture/OVERVIEW.md` (`.claude/skills/` line).

### snapshot-saver-doc-claims-wrong-isolation
- Type: drift
- Area: ios
- Order: 270
- Source: PR for tm-robustness-d7-main-actor-task
- Problem: The doc comment of `writeMapSnapshot` in `iosApp/Packages/Tracking/Sources/Tracking/MapSnapshotSaver.swift` says the app target builds with `NonisolatedNonsendingByDefault`, so the function runs on its caller's actor. The function is defined in the `Tracking` package, whose `Package.swift` (swift-tools-version 5.9, no `swiftSettings`) does not set it; only the app target sets `SWIFT_APPROACHABLE_CONCURRENCY = YES` (`project.pbxproj`). So the original statement (a nonisolated `async` function runs on the global executor) may have been right for that module. Read from the files, not compiled. Changing the comment is a Swift change and would start the iOS jobs, so it is not done in the PR that found it.
- Done when: the comment says what is true for that module (the call site's `Task.detached` stays), in a PR that may touch iOS code.
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/MapSnapshotSaver.swift` (`writeMapSnapshot`); `iosApp/Packages/Tracking/Package.swift`; `iosApp/TrailMetrics.xcodeproj/project.pbxproj`; `tm-robustness` D7.

### detekt-exception-name-exemption-undocumented
- Type: drift
- Area: .claude/skills/tm-robustness, config
- Order: 310
- Source: sweep tm-robustness
- Problem: `tm-robustness` E2's Enforced line says detekt `SwallowedException` does not check "an exception named `_`", and E1's names `TooGenericExceptionCaught` with no exemption. detekt 1.23.8's default for both rules is `allowedExceptionNameRegex: '_|(ignore|expected).*'`, and `config/detekt/detekt.yml` (`buildUponDefaultConfig = true`) does not override it. So a catch whose variable starts with `expected` or `ignore` is checked by neither rule. Five production `catch (expected: Exception)` blocks rely on it: `TrackingSessionManager` (`clearSession`, `persist`), `RestartAction.kt` (`handleRestart`), `MainActivity` (`handleStopTrackingIntent`), `SavedSessionOfferViewModel` (`init`). Each was read: each handles its failure on purpose, so none is an E1 or E2 violation (the E4 side is `tracking-session-store-failures-not-surfaced`). Only the rule text is wrong. Not fixed: this sweep changes no skill or config, and narrowing the regex (lint config, protected) or documenting it is a decision.
- Done when: E1's and E2's Enforced lines name the `expected`/`ignore` name exemption, or `config/detekt/detekt.yml` sets `allowedExceptionNameRegex: '_'` for both rules and the five catches are renamed or suppressed with approval.
- Refs: `.claude/skills/tm-robustness/SKILL.md` (E1, E2); `config/detekt/detekt.yml`; `build.gradle.kts` (`buildUponDefaultConfig`); the five files above.

### route-error-module-stated-as-core
- Type: drift
- Area: CLAUDE.md, .claude/skills/tm-kmp-shared
- Order: 340
- Source: sweep tm-kmp-shared
- Problem: `CLAUDE.md` ("Map": "`core` commonMain only: `AppRoute`, `RouteError`/`RouteUiError`") and `tm-kmp-shared` ("Module boundaries": "`core` (commonMain only): `AppRoute`, `RouteError`/`RouteUiError`") say `RouteError` is in `core`. It is in `domain` (`domain/src/commonMain/.../domain/model/RouteError.kt`); `core` holds only `AppRoute.kt` and `RouteUiError.kt`. The same skill's "Existing error model" and `core/README.md` call it domain-level, so the texts also disagree with each other. Not fixed: this sweep changes no skill and no `CLAUDE.md`.
- Done when: both lines name only `AppRoute` and `RouteUiError` for `core` (and `RouteError` under `domain`), matching `find core/src -name '*.kt'`.
- Refs: `CLAUDE.md` ("Map"); `.claude/skills/tm-kmp-shared/SKILL.md` ("Module boundaries"); `core/README.md`; `domain/.../model/RouteError.kt`.

### android-viewmodel-count-stale
- Type: drift
- Area: CLAUDE.md, .claude/skills
- Order: 350
- Source: sweep tm-kmp-shared
- Problem: Four texts count the Android ViewModels as four: `CLAUDE.md` ("Presentation layer: MVI": "All four Android ViewModels"), `tm-android` (MVI "Current code: all four ViewModels follow this shape"), `tm-robustness` M2 ("the four ViewModels hold none") and `tm-pr-workflow` Boundaries ("All four Android ViewModels are on MVI since #54"). There are five: `SavedSessionOfferViewModel` (`androidApp/app`) was added later, with `state`, `onAction` and `events`. The claims still hold for it as read here (MVI shape, no `Context`), only the count and the lists of names are stale. Not fixed: this sweep changes no skill and no `CLAUDE.md`.
- Done when: the four texts name all five ViewModels or drop the count, matching `grep -rn 'class .*ViewModel' androidApp/*/src/main`.
- Refs: `CLAUDE.md`; `.claude/skills/tm-android/SKILL.md`; `.claude/skills/tm-robustness/SKILL.md`; `.claude/skills/tm-pr-workflow/SKILL.md`; `androidApp/app/.../SavedSessionOfferViewModel.kt`.

### android-skill-koin-and-count-text-stale
- Type: drift
- Area: .claude/skills/tm-android
- Order: 440
- Source: sweep tm-android
- Problem: Two statements in `tm-android` ("Koin") disagree with the code. (1) "Today every module uses the lambda form, including `HistoryViewModel` and `RouteViewModel`": `androidApp/app`'s `appModule` registers `SavedSessionOfferViewModel` with `viewModelOf(::SavedSessionOfferViewModel)`, so the lambda form is not used by every module. (2) "Existing exception: `MainActivity` field-injects `TrackingSessionManager` with `by inject()`": `MainActivity` field-injects three dependencies (`trackingSessionManager`, `applicationScope`, `logger`), so the exception line names one of three. Count 2 lines. The "four ViewModels" count of the same skill is already `android-viewmodel-count-stale`. Not fixed: this sweep changes no skill.
- Done when: the lambda-form sentence names the modules that still use it (`routeModule`, `historyUiModule`, `trackingUiModule`) and the `MainActivity` exception lists the three injected fields, or both lines are removed with the code fixes `android-viewmodels-koin-lambda-form` and `android-mainactivity-field-injection`.
- Refs: `.claude/skills/tm-android/SKILL.md` ("Koin", "Known deviations"); `androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/di/AppModule.kt`; `androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/MainActivity.kt`; `android-viewmodel-count-stale`.

### ios-skill-cast-exception-too-narrow
- Type: drift
- Area: .claude/skills/tm-ios
- Order: 510
- Source: sweep tm-ios
- Problem: `tm-ios` "Architecture" says: never an `as?`/`is` cast on an abstraction to reach a concrete type, and "decoding a bridged Kotlin exception, as `RouteViewModel`'s `underlyingRouteError` does, is the one exception". Three more casts in production Swift are not that: `RouteViewModel` tests `error is CancellationError` in a `catch` (Swift concurrency cancellation), `RouteMapView` casts `marker.userData as? RoutePoint` (the Google Maps API stores `Any?`), and `RouteMapConfiguration` casts the Info.plist value `as? String`. Count 3, all forced by an Apple or Google API returning an abstraction. Read as not violations of the rule's intent, so the text is wrong, not the code. Not fixed: this sweep changes no skill.
- Done when: the sentence lists these kinds of cast (a cast required by a system or SDK API that returns `Any`, and Swift's `CancellationError` check) or says "unless the API returns an abstraction", matching `grep -rn -E ' as\? | is [A-Z]' iosApp/Packages/*/Sources`.
- Refs: `.claude/skills/tm-ios/SKILL.md` ("Architecture"); `iosApp/Packages/Route/Sources/Route/RouteViewModel.swift`, `.../RouteMapView.swift`, `.../RouteMapConfiguration.swift`.

### tm-testing-junit5-decision-not-in-docs
- Type: drift
- Area: .claude/skills/tm-testing
- Order: 530
- Source: sweep tm-testing
- Problem: `tm-testing` ("Stack") says "No JUnit5 anywhere in this project (evaluated and rejected, see `docs/architecture`)". `docs/architecture` (`ADR-001`, `ADR-002`, `ADR-003`, `OVERVIEW.md`) has no mention of JUnit, JUnit 5 or Jupiter (`grep -rni junit docs/architecture` returns nothing); the only docs that name JUnit4 are in `docs/epics/mvi-presentation-migration.md`. The rule itself holds in the code (no Jupiter import, no Jupiter entry in the version catalog), so only the pointer is wrong. Count 1 line. Not fixed: this sweep changes no skill, and `docs/architecture` is protected (an ADR that records the decision would be a new document).
- Done when: the sentence drops "evaluated and rejected, see `docs/architecture`" or points at an ADR that records the decision, so that `grep -rni junit docs/architecture` agrees with the skill text.
- Refs: `.claude/skills/tm-testing/SKILL.md` ("Stack"); `docs/architecture/`; `CLAUDE.md` ("Testing stack").
