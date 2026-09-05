# KMP Migration — Learnings

Real gotchas and decisions hit while converting TrailMetrics to Kotlin Multiplatform.
Written for interview prep — each entry should answer "why did you do it this way?"

---

## AGP 9.0+ requires a dedicated plugin for KMP Android targets

`com.android.library` + `org.jetbrains.kotlin.multiplatform` together is no longer
supported since AGP 9.0. Must use `com.android.kotlin.multiplatform.library` instead,
with Android target config moved into `kotlin { android { ... } }` (replaces the
separate `androidTarget()` + top-level `android {}` block).

Also: the JVM-only test source set is now called `androidHostTest`, not `androidUnitTest`
(the old name from the `com.android.library` + KMP combo).

---

## `commonMain` being free of `android.*` imports doesn't mean it's platform-agnostic

Kotlin code with zero Android imports can still be secretly JVM-only, because Kotlin
stdlib itself isn't 100% shared:

- `Math.toRadians()` etc. — that's `java.lang.Math`, JVM-only. Cross-platform
  replacement: `kotlin.math.*` (has `PI`, `sin`, `cos`, `atan2`, `sqrt`, `pow`, but
  no `toRadians` — trivial to write manually: `degrees * PI / 180`).
- `"%.2f".format(value)` (`String.format`) — relies on `java.util.Formatter`, JVM-only.
  **No cross-platform equivalent exists in kotlin-stdlib-common** — this is a real,
  known gap (deliberate: locale-aware number formatting isn't something stdlib-common
  standardizes). Three common fixes:
    1. Write a manual fixed-point formatter in pure Kotlin (round before splitting
       int/fraction parts to avoid truncation bugs — used here, see
       `MetricsFormatter.formatFixed`)
    2. `expect`/`actual` per platform, delegating to each platform's native formatter
    3. A third-party KMP library (no de facto standard exists, unlike e.g.
       `kotlinx-datetime` for dates)
       This project uses (1): app's formatting needs are simple (1-2 decimals, no locale
       requirement), so a manual formatter avoids adding `expect`/`actual` complexity for
       something this small.
- Lesson: the only way to be sure code is really shareable is to actually compile it
  for a second target (`./gradlew :domain:compileKotlinIosSimulatorArm64`) — reading
  the source isn't enough.

---

## Test migration deferred: `androidHostTest` (JVM-only) vs `commonTest`

`domain`'s existing tests (mockk + Truth + JUnit) were moved to `androidHostTest`
rather than `commonTest`, because none of those three test libraries publish
Kotlin/Native artifacts. Moving code to `commonMain` only proves it *compiles* for
iOS — it says nothing about whether it's *correct* there, since no test currently
runs on the iOS target.

Tracked as follow-up: migrate to `commonTest` using `kotlin.test` assertions and 
hand-written fakes (for `LocationRepository`, `Clock`, `Logger`,
`TrackingServiceLauncher`) in place of `mockk`.

---

## Migration surfaced a pre-existing test gap: order-insensitive assertions on ordered data

While converting Truth's `containsExactly(...)` (order-independent by default,
unless `.inOrder()` is chained) to kotlin.test, found that all 9 usages across
RouteProgressTest and UpdateTrackingStateUseCaseTest lacked `.inOrder()` — meaning
they never verified point order, despite asserting on GPS path data where order is
semantically meaningful (a traveled path isn't the same if points are reordered).

Preserved the original (order-insensitive) behavior during this migration to keep
it a pure library swap. Tracked as follow-up: tighten these assertions to check
order too, since it's a real correctness gap independent of KMP.

---

## Kotlin/Native restricts characters in backtick test names

JVM tests with backtick-quoted display names (e.g. `` `does X, updates Y` ``) allow
almost any character, since the name is just a JVM method name. Kotlin/Native
rejects some characters (comma confirmed: "Name contains illegal characters: ',''")
at compile time — the name has to work as an exported symbol usable from
Objective-C/Swift, which doesn't allow commas in identifiers.

Practical rule: avoid commas (and likely other punctuation) in backtick test names
for any file under commonTest, since it must compile for both JVM and Native
targets. Use "and" or spaces instead.

---

## iOS Simulator tests require a runtime download, separate from Xcode itself

Installing Xcode does not include any iOS Simulator runtime by default (confirmed:
`xcrun simctl list runtimes` returned empty on a fresh Xcode install). Kotlin/Native
test tasks like `iosSimulatorArm64Test` need an actual runtime to boot a simulator
against.

Fix: `xcodebuild -downloadPlatform iOS` (or Xcode > Settings > Platforms > iOS).
Direct analogy to Android: this is the iOS equivalent of downloading a system image
via the Android SDK Manager before an AVD can boot.

---

## Manual fakes over mocking frameworks for KMP

mockk (like Truth/JUnit) has no Kotlin/Native artifacts, so mocked dependencies
in tests had to become hand-written fakes to run in commonTest. Two design
decisions worth remembering:

1. **Fakes need mutable behavior, not just mutable state.** A first pass at
   `FakeClock` took its return sequence via constructor (`FakeClock(vararg values)`),
   mirroring how mockk's `every {}` is called per-test. But the object under test
   is often constructed once in `@BeforeTest`, before each test's specific
   values are known. Fix: expose a `setValues(...)` method that can be called
   from within each test, after construction — matching the timing of mockk's
   per-test `every {}` calls rather than the timing of object creation.

2. **Not every dependency needs a fake.** `CalorieCalculator` is a concrete,
   pure, deterministic class (no I/O) — it was left as a real instance in
   `SaveActivityUseCaseTest` rather than mocked/faked. Rule of thumb: fake or
   mock only at I/O boundaries (network, disk, sensors, system clock); pure
   logic should just be used directly, since fixture behavior for it doesn't
   need faking and its correctness is covered by CalorieCalculatorTest already.
   Bonus: computing the test's expected value by calling the real calculator
   (instead of hardcoding a number) keeps the test resilient to intentional
   formula changes and catches accidental ones.

---

## Phase A (domain module) complete

`domain` is now a fully verified KMP module: all production code compiles for
Android + iOS, and all 7 test files run (not just compile) on both
`testAndroidHostTest` and `iosSimulatorArm64Test`, using kotlin.test + hand-written
fakes instead of JUnit/Truth/mockk. Zero JVM-only test dependencies remain.

Next: Phase B (data module) — Ktor engine swap, Room KMP driver, and designing
expect/actual boundaries for SharedPreferences, Play Services Location, and the
Android foreground Service (per the original ClaudeCode investigation report).

---

## AGP's built-in Kotlin doesn't support BuildConfig for KMP Android modules

`com.android.kotlin.multiplatform.library` has no BuildConfig feature at all —
Google's own docs confirm this is intentional: the plugin is "variant-agnostic"
(no build types/flavors), and BuildConfig is inherently a variant-scoped concept.
Official recommendation: use a third-party plugin like BuildKonfig, or a custom
Gradle task.

Chose BuildKonfig (`com.codingfeline.buildkonfig`) since it natively supports the
exact split needed here: `defaultConfigs` for values shared across platforms
(`DIRECTIONS_API_KEY`), and `targetConfigs { create("android") { ... } }` for
values that only make sense on one platform (`ANDROID_CERT_SHA1`). Under the
hood it generates a real `expect`/`actual` `BuildKonfig` class per source set —
exactly the pattern we'd have hand-written with `expect`/`actual`, just automated.

---

## AGP 9's "built-in Kotlin" sets a Kotlin Gradle Plugin floor (2.2.10), not a ceiling

AGP 9.0+ has a runtime dependency on KGP 2.2.10 and will auto-upgrade a lower
project Kotlin version to match — this is a *minimum*, not a strict pin. This
was easy to misdiagnose as "AGP won't allow a Kotlin version other than 2.2.10."

The actual conflict encountered was different: a Kotlin Gradle plugin dependency
(BuildKonfig, at any version tried) required a newer transitive `kotlin-gradle-plugin`
than the version Gradle's own embedded Kotlin (used for kotlin-dsl script
evaluation) allows, causing an `org.jetbrains:annotations` version conflict
("Pinned to the embedded Kotlin"). Downgrading BuildKonfig repeatedly only shifted
which KGP version it wanted — it never fixed the underlying mismatch. The actual
fix: bump the project's own Kotlin version high enough (2.4.10) that every
plugin's requirement lines up consistently across the whole buildscript classpath.

Lesson: a version conflict naming a specific transitive artifact (not the plugin
you're adding) is a signal to check the *whole* dependency graph's alignment,
not just retry different versions of the one plugin you just added.

---

## KSP decoupled its versioning from Kotlin's around Kotlin 2.3

Older KSP releases used a joined `<kotlin-version>-<ksp-version>` scheme (e.g.
`2.2.10-2.0.2`), requiring an exact-matching KSP release for every Kotlin version.
Starting around Kotlin 2.3, KSP switched to independent version numbers (e.g.
`2.3.11`) that support a *range* of Kotlin versions internally (KSP2 is built on
the Kotlin Analysis API, which is less tightly coupled to a specific compiler
build). Check the real published version list
(`com.google.devtools.ksp.gradle.plugin` on Maven) rather than guessing a
`<kotlin>-<ksp>` string for recent Kotlin versions — it may no longer exist in
that format.

---

## `platform(...)` needs a `project.dependencies.` prefix inside KMP source set blocks

`commonMain.dependencies { }` (and other KMP source set dependency blocks) use
`KotlinDependencyHandler`, not Gradle's normal `DependencyHandler` — so the usual
`platform(libs.someBom)` helper isn't in scope. Fix: `project.dependencies.platform(libs.someBom)`,
which reaches back to the project's real `DependencyHandler` where `platform()`
is defined.

---

## Task names differ between `domain` and `data` under the same KMP Android plugin

`domain`'s Android-target compile task is `compileKotlinIosSimulatorArm64` /
implied `compileKotlinAndroid`-style naming, but `data`'s equivalent turned out
to be `compileAndroidMain` — a different naming convention for what's
conceptually the same operation, likely because `data` has additional KSP-driven
source generation folded into that task's name. Lesson (repeated from Phase A):
never guess a task name for this plugin — always confirm with
`./gradlew :<module>:tasks --all`.

---
