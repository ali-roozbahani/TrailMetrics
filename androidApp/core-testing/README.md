# androidApp/core-testing

Plain Android library module holding test fakes shared by two or more
`androidApp/feature-*` JVM test source sets. The Android counterpart of
`iosApp/Packages/TestSupport`.

**Consume it only with `testImplementation(project(":androidApp:core-testing"))`.**
Never add it as an `implementation`/`api` dependency of any module, and never to
`:androidApp:app`: it must stay out of the production APK graph.

## What lives here

- `FakeActivityHistoryRepository`: used by `feature-history` and `feature-tracking`.
- `FakeLocationRepository`: used by `feature-route` and `feature-tracking`.
- `FakeUserProfileRepository`: used by `feature-route` and `feature-tracking`.

A fake or fixture used by a single feature stays in that feature's
`src/test/.../fakes/` until a second feature needs it.
