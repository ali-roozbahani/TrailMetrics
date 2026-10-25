# androidApp/core-testing

Plain Android library module holding test fakes shared by two or more
`androidApp` JVM test source sets. The Android counterpart of
`iosApp/Packages/TestSupport`.

**Consume it only with `testImplementation(project(":androidApp:core-testing"))`.**
Never add it as an `implementation`/`api` dependency of any module: it must stay out of the
production APK graph. `:androidApp:app` consumes it the same way, through `testImplementation`.

## What lives here

- `FakeActivityHistoryRepository`: used by `feature-history` and `feature-tracking`.
- `FakeLocationRepository`: used by `feature-route` and `feature-tracking`.
- `FakeUserProfileRepository`: used by `feature-route` and `feature-tracking`.
- `FakeClock`, `FakeLogger`, `FakeTrackingServiceLauncher`, `FakeTrackingSessionStore`: used by
  `feature-tracking` and `app`.

A fake or fixture used by a single feature stays in that feature's
`src/test/.../fakes/` until a second feature needs it.
