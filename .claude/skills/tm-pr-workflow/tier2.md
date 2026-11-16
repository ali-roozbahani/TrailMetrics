# Tier 2: what automated tests cannot show

Moved word for word from `SKILL.md`, "Tier 2". The rules are unchanged.

The user-visible behavior of a change (a screen, a ViewModel state, a navigation, a
notification text), on each platform it touches, is validated by automated tests: unit,
integration and UI tests (`tm-testing`), not by a human on a device. The agent has no device
and never runs the feature on one itself. A human check is listed only for one of these
reasons:

1. **No automated test can observe it.** In this repo: real GPS hardware and the platform
   location providers (every test uses a fake `LocationRepository`); what the real Maps SDK
   draws (Compose UI tests show the map as an empty `Box` or a shadowed `MapView`, and the
   map's content is not asserted, on iOS either); OS-level permission dialogs, the
   tracking notification and the iOS Live Activity (`TrackingWidget`); and a human judgement
   of visual design against Figma.
2. **A test seam or test target that does not exist yet.** It must be tracked by a queued
   PR or a `BOARD.md` record ("Board", rule 1) that the PR names. The iOS UI-test target `TrailMetricsUITests` has a
   launch test and the scenarios landed so far (Details delete, Route, Tracking), and the app
   has its launch-time fake seam (the `UITEST_SEAM` entry); the other scenarios land with later
   subtasks of `docs/epics/ios-ui-tests.md`, so an iOS-only user-visible behavior whose logic no
   Swift unit test in the packages covers and no scenario reaches may still need this.
3. **The single final smoke check of a finished end-to-end feature**, after all its automated
   tests passed. It is a smoke check, not the validation.

For each human check the PR gives the behavior, the reason (1, 2 with its PR, queue entry or
record, or 3) and the exact steps. For docs-, test-, CI- or skill-only changes, say plainly that nothing
user-visible changes (see #32, #35).
