# Performance and efficiency (P1 to P6, P8, P9)

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the section "Performance and efficiency". The rules are unchanged; they are still cited as `tm-robustness`, rules P1 to P6, P8 and P9.

## Performance and efficiency

- **P1** Compose: a stable `key` in every lazy list (`LazyColumn`, `LazyVerticalGrid`). Why: without
  it items lose state and recompose on reorder. Example: `HistoryScreen` (`key = { it.id }`).
  Enforced: reviewer only. Severity: important.
- **P2** Compose: no heavy work or allocation in composition; `remember` or `derivedStateOf` for a
  derived value; read state as late as possible; no new lambda or object per item where it breaks
  skipping. Why: composition runs on every state change. Example: `RoutePolyline`
  (`remember(points) { ... }`). Enforced: reviewer only. Severity: important.
- **P3** SwiftUI: a cheap `body`, observation as narrow as the state, no heavy work in `body`. Why:
  `body` runs on every published change. Example: no example yet. Enforced: reviewer only.
  Severity: important (blocking when it blocks the main actor: D6).
- **P4** A per-location-update or per-tick path allocates little and is conflated or sampled before
  it reaches the UI (map polylines especially). Why: it runs for as long as the session. Example:
  no example yet (see "Known deviations in the current code", `SKILL.md`). Enforced: reviewer only. Severity: important.
- **P5** Room: queries run off the main thread, a filtered or sorted column has an index, no query
  per item (N+1), no loading a whole table for one row. Why: query cost grows with the table.
  Example: `ActivityDao.getById` (primary key); the sorted `startedAtEpochMillis` has no index (see
  "Known deviations in the current code", `SKILL.md`). Enforced: reviewer only; a new index is a schema change (`tm-kmp-shared`).
  Severity: important.
- **P6** Battery: the location priority and interval are the lowest that meet the feature, and
  updates stop when no screen or session needs them. Why: location is the largest battery cost.
  Example: `TrackingSessionManager.pause` cancels the observation. Enforced: reviewer only.
  Severity: important.

- **P8** Compose: no `@Stable` or `@Immutable` and no `ImmutableList` parameter by reflex. Why: with
  strong skipping a parameter that is not stable is compared by instance, which is cheap; an annotation
  makes the compiler call `equals`, which on a collection walks every element and can cost more than
  the recomposition it saves. Example: none in `androidApp`. Enforced: reviewer only. Severity: important.
- **P9** Compose: no write to state after a read of it in composition, and none from `onSizeChanged` or
  `onPlaced` into state that composition reads. Why: the write invalidates what was just composed, so a
  frame is drawn wrong or composition repeats. Example: no example yet. Enforced: reviewer only. Severity:
  important.
