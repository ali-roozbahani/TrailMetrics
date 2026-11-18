# Compose UI tests: the rules

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the section "Compose UI tests". The rules are unchanged; they are still cited as `tm-testing`, "Compose UI tests".

## Compose UI tests

When you write or change a Compose UI test, read `compose-ui-tests.md` first: the robot example,
the real-ViewModel screen-test setup, the double-tap reasoning and the Maps shadow details.

- `ComposeTestRule`, JUnit4 (`@get:Rule`). Use the Robot pattern once a screen has 3+ UI test cases
  or several tests share setup/assertion sequences: one robot class per screen, every method returns
  `this` for chaining. Don't reach for it for a 1-2 assertion smoke test: plain
  `composeTestRule.setContent { ... }` + a couple of `onNodeWith...` calls is clearer there.
- Screen tests run the real ViewModel (`feature-history`'s `DetailsScreenTest`/`HistoryScreenTest`
  are the pattern to copy): `@RunWith(RobolectricTestRunner::class)`, `@Config(sdk = [35])` (add
  `qualifiers = "w411dp-h891dp"` when a `LazyColumn` must compose several rows) and
  `createAndroidComposeRule<ComponentActivity>()`, so strings come from
  `rule.activity.getString(...)` instead of being copied into the test.
- Test the `<X>Root`, not only the stateless `<X>Screen`, so event handling (navigation callback,
  snackbar) is covered. `@Before` sets the main dispatcher and starts Koin with the feature's UI
  module plus fakes from `core-testing`; `@After` calls `stopKoin()` and `resetMain()`. Navigation
  lives in `androidApp/app`, so assert on the Root's callback (count its calls).
- Hold a suspending call with the fake's gate (a `CompletableDeferred` the fake awaits). Act,
  assert nothing happened yet, `complete(Unit)`, `rule.waitForIdle()`, assert. No `Thread.sleep`,
  no real delays.
- Double tap: `performTouchInput { down(center); up(); down(center); up() }`, never
  `click(); click()` (the first tap's recomposition can remove the button, so the test passes with
  or without the guard). Check it once by removing the guard in the working tree: the test must
  fail on the doubled call.
- Maps: when the test needs no map callback, wrap the content in
  `CompositionLocalProvider(LocalInspectionMode provides true)`; the map's content is not tested and
  no production seam is needed. When the test must drive a map callback (`MapEffect`,
  `GoogleMap.snapshot { }`), render the map as `TrackingScreenSnapshotTest` does, with test sources
  only (its `ShadowMapView` must extend `ShadowViewGroup`). A test that renders no map and must see
  an uninitialized Maps SDK (`TrackingScreenTest`) calls `FakeGoogleMap.uninstallFactories()` first.
- Find nodes by visible text and content description first; a `testTag` is a production
  change, so only when nothing else identifies the node. A merged node (a clickable `Card`)
  matches every text inside it: assert a row with `hasText(a) and hasText(b) ...`.
