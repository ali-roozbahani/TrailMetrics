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

Notes on the example: S2 and S3 don't need `androidApp/app/**` or `iosApp/TrailMetrics/**`
because History is already routed on both platforms. If a feature needed a new screen
route, that wiring would be a separate subtask after S2/S3, or it would go into exactly
one of them.
