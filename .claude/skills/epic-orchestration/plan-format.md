# Epic plan: format and worked example

Read from `SKILL.md`, "The plan". The rules are there; this file holds the plan file's format and a worked example.

````markdown
# Epic: <title>

- **Slug:** <epic-slug>
- **Integration branch:** feature/epic/<epic-slug>
- **Goal:** <one paragraph: what the user can do when this lands>
- **Out of scope:** <explicit list>
- **Approved by:** <human> on <YYYY-MM-DD>

## Subtasks

```yaml
- id: S1
  title: <imperative summary>
  branch: <feature|bugfix|chore>/<epic-slug>-<subtask-slug>
  skills: [tm-kmp-shared, tm-testing]
  depends_on: []
  gate_with: []   # the ids of subtasks whose interim state only works together with this one (see below); [] when none
  duties:         # the duties of the old owner that this subtask must cover (see "Responsibilities moved"); [] when it moves none
    - <duty>
  allowed_paths:
    - <glob>
  acceptance:
    - <checkable statement>
  tier2: <the automated tests that cover the subtask's user-visible behavior, or the human
    check with its reason (`tm-pr-workflow` Tier 2), or "none — <why>">
```

## Waves

- Wave 1: S1
- Wave 2: S2 ∥ S3   (disjoint: <one line on why>)

## Responsibilities moved (required; "none" when no subtask moves one)

For each responsibility a subtask moves (state, a decision, a side effect, a timer, an outside resource) from one component or
layer to another: one block of the five questions below. Each answer is one line, `duty -> new owner -> proof`.

- **Responsibility:** <what moves> (old owner <A>, new owner <B>, subtask <id>)
- **1. Lifetime.** Does B live longer than A? If so, every event that ends or restarts what B holds (save, discard, restart, abandon,
  process death and restore) and who clears it in each: <event -> who clears it -> proof>
- **2. Ordering and timing.** What ordering, delay or batching did A provide as a side effect, and does anything depend on it? <duty -> B -> proof>
- **3. External resources.** What outside the code is alive because of this (a notification, a service, a listener, a location or
  sensor subscription, a file, a timer), and who releases it, in what order, on every exit path (normal, error, cancel, ended by the
  system)? <resource -> releaser and order -> proof>
- **4. Threads and contexts.** On which thread or dispatcher does the code that is now called run, and did the move change it? <call -> context before and after -> proof>
- **5. Exit paths.** Do all of them end in the same clean state? <path -> state -> proof>

A proof is a test by name, or, for behavior that only shows on a device or emulator (questions 2 to 4), repeated runs of the real
scenario that read the system's own state (the platform's notification list, its service list, its location clients: not only the
app's), with the number of runs and the count of failures reported (for example "36 runs, 0 failures"). An answer that
is not known is written as `open risk: <what is unknown>`, never left out. The subtask's `duties` list is these lines' duties: the
worker's brief carries it, and the local review asks whether the diff covers each (`tm-pr-review`, item 16).

## Existing tests that pin behavior the epic removes (required; "none found" says how it was searched)

The plan lists the existing tests that assert behavior the epic changes or removes, found by what they assert, not only by tests that
name a changed symbol: search the tests for the behavior (the state a screen shows after an action, the sequence a fake records, the
count of calls), in every module and platform the epic touches. Each entry: the test's full name, what it asserts, and what happens to
it (kept, changed in a named way, deleted with the reason). A red test that the plan did not name is a stop of the subtask
(`running-an-epic.md`, "3. The wave loop", step 4), so a test the plan does not name costs a stop. The first epic's example is in `LEARNINGS.md`. A test name the plan writes is the
name the test will have, or the plan marks it `(provisional)`; a native Kotlin test name, for one, cannot contain a comma.

## Subtasks with an interim state

A subtask whose result only works together with another's (one half of a contract that is wrong until the other half lands) is listed in the other's `gate_with` and the other in its own: the plan gates them together
from the start, as one integration unit (the gate runs once on the combination, each is reviewed on its own and merged on the combination's gate result, the
earlier one first: `subtask-merge.md`, step 7). The first epic's example is in `LEARNINGS.md`. A plan that leaves the pair separate and finds out at the first
gate has paid a stop for it.

## Acceptance coverage (optional)

| Goal criterion | Subtask | Check that proves it |
|---|---|---|
| <one criterion of the Goal> | <S1, S2, ...> | <the test by name, or the human check> |

## Re-plan trigger (optional)

- <the finding that means stop and write the plan again, and what the human is asked to decide>

## Epic-level Tier 2 (on the integrated branch before merge to main)

- <end-to-end behavior across both platforms and the automated test that covers it>
- <human checks with their reasons, and the final smoke check>
````

### Worked example: personal records on History

The feature: History on both platforms shows the user's longest distance and fastest
average pace across saved activities.

````markdown
# Epic: Personal records on History

- **Slug:** personal-records
- **Integration branch:** feature/epic/personal-records
- **Goal:** Both History screens show a "Personal records" section (longest distance,
  fastest average pace) computed once in `domain` from `ActivityHistoryRepository`.
- **Out of scope:** persisting records;
  records per `ActivityType`; any change to Tracking or Route.
- **Approved by:** <human> on 2026-10-01

## Subtasks

```yaml
- id: S1
  title: Add GetPersonalRecordsUseCase and expose it to both platforms
  branch: feature/personal-records-shared
  skills: [tm-kmp-shared, tm-testing]
  depends_on: []
  allowed_paths:
    - domain/src/commonMain/**/model/PersonalRecords.kt
    - domain/src/commonMain/**/usecase/GetPersonalRecordsUseCase.kt
    - domain/src/commonTest/**/usecase/GetPersonalRecordsUseCaseTest.kt
    - data/src/commonMain/**/di/UseCaseModule.kt
    - shared/src/iosMain/**/di/KoinHelper.kt
  acceptance:
    - PersonalRecords is a pure domain model; GetPersonalRecordsUseCase reads
      ActivityHistoryRepository and returns null fields when history is empty.
    - kotlin.test cases cover empty history, one activity, ties, and zero-distance
      activities, using the existing FakeActivityHistoryRepository.
    - Bound in useCaseModule; KoinHelper has a concrete getPersonalRecordsUseCase().
  tier2: none — no UI yet

- id: S2
  title: Show personal records on Android History
  branch: feature/personal-records-android
  skills: [tm-android, tm-testing]
  depends_on: [S1]
  allowed_paths:
    - androidApp/feature-history/**
  acceptance:
    - HistoryScreen shows the section above the list; hidden when there is no history.
    - The records are new HistoryState fields only; HistoryViewModel keeps its MVI
      shape (no new public method besides onAction).
    - HistoryUiModule gets the use case via Koin; ViewModel test covers both states.
  tier2: HistoryScreenTest (Compose UI, Robolectric): empty history → no section; two saved
    activities → values match. HistoryViewModelTest covers both states.

- id: S3
  title: Show personal records on iOS History
  branch: feature/personal-records-ios
  skills: [tm-ios]
  depends_on: [S1]
  allowed_paths:
    - iosApp/Packages/History/Sources/**
    - iosApp/Packages/History/Tests/**
  acceptance:
    - HistoryViewModel resolves the use case via a KoinHelper default-parameter init.
    - HistoryView shows the same section with the same empty-state rule as Android.
  tier2: Swift unit tests of HistoryViewModel in HistoryTests: empty history → no records;
    two saved activities → values match. Human check (the iOS UI-test target has no
    scenario for this screen yet): HistoryView hides the section with empty
    history and shows the values of two saved activities.
```

## Waves

- Wave 1: S1
- Wave 2: S2 ∥ S3   (disjoint: androidApp/feature-history/** vs iosApp/Packages/History/**;
  neither touches app/, TrailMetrics/, the xcodeproj or the shared layer)

## Epic-level Tier 2

- The records are computed once, in `domain`: GetPersonalRecordsUseCaseTest runs on the
  Android host and the iOS simulator.
- Deleting the record-holding activity updates the section: a HistoryScreenTest case on
  Android, a HistoryViewModel unit test on iOS; on iOS the View's update is a human check
  (the iOS UI-test target has no scenario for this screen yet).
- Final smoke check: the same data on both platforms shows identical records and formatting.
````

The two optional sections ("Acceptance coverage" and "Re-plan trigger") may be left out: a plan without
them is valid. The table gives every criterion of the Goal a subtask and the check that proves it, so a
criterion that no subtask covers shows as an empty row. The trigger names what the orchestrator finds
while it works (a contract that has to change, a subtask that needs a path outside its `allowed_paths`, a
check that cannot be written) that sends the plan back to the human instead of being patched in the
subtasks.

Notes on the example: S2 and S3 don't need `androidApp/app/**` or `iosApp/TrailMetrics/**`
because History is already routed on both platforms. If a feature needed a new screen
route, that wiring would be a separate subtask after S2/S3, or it would go into exactly
one of them.
