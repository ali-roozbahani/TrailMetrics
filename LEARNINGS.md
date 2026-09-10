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

## kotlin.time.Clock replaced the need for kotlinx-datetime for simple "current time" needs

Since Kotlin 2.1.20, `kotlin.time.Clock` and `kotlin.time.Instant` are part of the
standard library itself — no external dependency needed for basic "get current
time as epoch millis" use cases (`Clock.System.now().toEpochMilliseconds()`).

Initially added `kotlinx-datetime` as a dependency for this (following older,
common advice), then discovered it wasn't needed: on a recent Kotlin version
(2.4.10 here), IDE flagged `kotlinx.datetime.Clock` itself as deprecated in favor
of `kotlin.time.Clock`. Removed the kotlinx-datetime dependency entirely.

Lesson: verify against current stdlib before reaching for a well-known
multiplatform library — some historically "you need a library for this" gaps
get closed by the language itself over time.

---

## `Dispatchers.IO` needs an explicit import for multiplatform code

`Dispatchers.IO` exists as a JVM-only direct member (internal on Native), but
kotlinx.coroutines also provides a genuinely multiplatform version as a
top-level extension property in the same package. Without an explicit
`import kotlinx.coroutines.IO`, common code resolves to the JVM member (which
fails to compile for Native targets with "internal in 'Dispatchers'").
Adding the explicit import switches resolution to the multiplatform extension
property, which has a real implementation for Native too — no need to fall
back to `Dispatchers.Default`.

---

## Kotlin/Native forbids mixing Objective-C and Kotlin supertypes in one class

A class can't simultaneously extend `NSObject` / implement an Objective-C
protocol (like `CLLocationManagerDelegateProtocol`) AND implement a pure Kotlin
interface (like domain's `LocationRepository`). Compiler error: "Mixing Kotlin
and Objective-C supertypes is not supported."

This is a fundamental object-model mismatch (Kotlin vtables vs Objective-C
message-passing), not a missing flag or workaround. Fix: split into two
classes using composition instead of one class using multiple inheritance --
a small private `NSObject`-based delegate class that only implements the
Objective-C protocol, held as a property inside the main class that
implements the pure-Kotlin interface. Callbacks flow from the private
delegate to the outer class via constructor-injected lambdas.

This pattern (private ObjC-interop delegate + composition) is the standard
approach any time a class needs to both consume a delegate-based Apple API
and satisfy a shared Kotlin interface -- not a one-off workaround for
CLLocationManager specifically.

---

## Phase B major milestone: hardest cross-platform boundary (Location) done

`LocationRepositoryImpl` (Android, FusedLocationProviderClient/Play Services,
callback-based) now has a full iOS counterpart (`IosLocationRepositoryImpl`,
CLLocationManager/CoreLocation, delegate-based) implementing the same
`LocationRepository` domain interface. Both compile and both modules
(:data:compileAndroidMain, :data:compileKotlinIosSimulatorArm64) pass.

Remaining data module work: TrackingService (Android foreground service --
no iOS equivalent exists, will need a different mechanism entirely for
background tracking on iOS), UserProfileRepositoryImpl (SharedPreferences ->
NSUserDefaults), and their DI modules.

---

## iOS has no equivalent to Android's persistent ongoing notification

Android's foreground Service + `NotificationCompat.setOngoing(true)` pattern
(a silent, continuously-updating notification) has no direct iOS counterpart.
`UNUserNotificationCenter` is designed for one-shot alerts; repeatedly
re-posting one to show live status would spam the user with interruptions.

The real iOS analog is **Live Activities** (ActivityKit, Lock Screen +
Dynamic Island), but it's a Swift-only, async/await-based framework not
practical to drive from Kotlin/Native. Decision: implement only the
background-location mechanism in the KMP data module
(`CLLocationManager.allowsBackgroundLocationUpdates`), and defer any
Live Activity UI to the native SwiftUI app layer (Phase D) -- notification
presentation is inherently a platform-UI concern here, not shared logic.

---

## Robolectric + Room's BundledSQLiteDriver conflict (UnsatisfiedLinkError)

Room's BundledSQLiteDriver loads a real native SQLite library at runtime.
Robolectric's own native runtime/classloader setup conflicts with this,
causing `UnsatisfiedLinkError` -- a known incompatibility, not a
misconfiguration on our part. Google's own docs explicitly say: "We don't
recommend Android local unit tests with Robolectric. Use local JVM tests
using Room KMP instead."

Fix: for pure database tests (no other Android API needed), drop
`@RunWith(RobolectricTestRunner::class)` entirely and use
`Room.inMemoryDatabaseBuilder<T>()` with no Context parameter -- Room KMP
supports Context-free in-memory builders specifically for plain JVM tests.
This runs faster too (no Robolectric simulation overhead).

Tests that need a genuine Android API (e.g. UserProfileRepositoryImplTest's
SharedPreferences) still legitimately need Robolectric -- this fix only
applies to Room/database tests.

---

## Room 3.0.2 doesn't publish iosX64 artifacts yet

Room 3.0's early stable releases (3.0.2 as of this writing) only ship KMP
artifacts for `iosArm64` and `iosSimulatorArm64` -- not `iosX64` (Intel
simulator). Since this target was already non-runnable on an Apple Silicon
Mac ("architecture mismatch" warnings throughout the domain/data KMP
migration) and Apple is phasing out Intel Mac support generally, removed
`iosX64()` from `data`'s target list rather than working around a
dependency gap for a platform with shrinking relevance. `domain` (no Room
dependency) still declares iosX64() without issue -- this is scoped to
modules that actually depend on Room.

---

## Room 3.0 renamed more than just the package

Beyond the androidx.room -> androidx.room3 namespace change, some annotations
were renamed outright, not just relocated: TypeConverter/TypeConverters
became ColumnTypeConverter/ColumnTypeConverters (identical semantics/usage,
new name). This wasn't documented clearly in the migration guide encountered
during this project's research -- discovered by decompiling the actual
3.0.2 artifact JAR when KSP reported a MissingType error. Lesson: for a
very recently released major version, verifying against the actual
compiled artifact can be more reliable than the migration docs, which may
lag behind the final API.

---

## BundledSQLiteDriver's Android artifact can't run under Robolectric (androidHostTest)

Room's BundledSQLiteDriver publishes a separate native binary per target,
including one specifically compiled for the Android runtime (ART/Bionic).
`androidHostTest` (Robolectric) only *simulates* Android APIs -- the actual
process is a plain JVM running on the host OS (macOS here), so the
Android-targeted native binary is ABI-incompatible with it
(UnsatisfiedLinkError: no sqliteJni in java.library.path). This is distinct
from iOS, where Kotlin/Native compiles tests directly to a real binary for
the actual iOS Simulator runtime -- no simulation layer involved.

Decision: rely on `commonTest` + `iosSimulatorArm64Test` for
ActivityHistoryRepositoryImplTest's coverage. Since the tested logic
(ActivityHistoryRepositoryImpl, Room queries) lives entirely in commonMain,
the iOS test run already verifies the exact same shared code that runs on
real Android devices -- androidHostTest coverage for this specific suite
would require converting it to a device/emulator instrumented test
(androidDeviceTest), which is a bigger step deferred for now.

---

## Phase B (data module) core migration complete

`data` now compiles on Android and iOS, with all repositories, DI modules,
and the Room database working on both platforms. Remaining before Phase B
is fully closed: migrate the two Robolectric-based tests
(ActivityHistoryRepositoryImplTest, UserProfileRepositoryImplTest) from
src/test to androidHostTest (they stay JVM-only, same reasoning as
domain's mockk-based tests -- Robolectric has no Kotlin/Native artifacts).

Full cross-module verification passed: :app:compileDebugKotlin succeeds,
confirming feature-route/feature-tracking/feature-history modules are
still compatible with the new data module surface.

---

## Phase C — Shared Module & XCFramework Export

- Umbrella module pattern: a dedicated `shared` KMP module (not `data`) owns
  DI composition and XCFramework export. `data`/`domain` stay focused on
  their own concerns; `shared` only aggregates + exposes `initKoin()`.
- `export()` in a Kotlin/Native framework block requires the exported
  module to be an `api(...)` dependency, not `implementation(...)` —
  otherwise its symbols aren't visible to Swift even with `export()`.
- Koin idiom for cross-platform composition root: `expect val platformModules`
    + a shared `fun initKoin(appDeclaration: KoinAppDeclaration = {})` in
      commonMain. Android calls `initKoin { androidContext(this) }`; iOS calls
      a `doInitKoinIos()` wrapper with no args. Feature-only (Compose UI) Koin
      modules stay out of `shared` and get passed via `appDeclaration` from
      the platform's real composition root (Android's `Application`).
- Inline `reified` functions like Koin's `get<T>()` do NOT export to
  Objective-C/Swift. Need a `KoinHelper : KoinComponent` bridge class in
  `iosMain` with concrete, non-generic getter functions per dependency.
- Kotlin `Flow<T>` exports to Swift as a near-unusable generic Objective-C
  type by default (no `for await`, generic type erased). SKIE
  (`co.touchlab.skie`, applied only in the framework-exporting module —
  here `shared`, not `domain`/`data`) rewrites Flow → Swift AsyncSequence
  and suspend fun → async/await in the generated header, with zero
  Kotlin-side code changes required.
- XCFramework must be rebuilt (`:shared:assembleTrailMetricsSharedDebugXCFramework`)
  after ANY change to `domain`, `data`, or `shared` source — Xcode does not
  know to do this automatically. Manual builds are risky to forget (solved
  in Phase D via an automated Run Script phase, see below).

---

## Phase D — iOS SPM Modularization + Xcode/Gradle Integration

- iOS equivalent of Gradle feature modules is local Swift Packages (SPM),
  one per feature, living under `iosApp/Packages/`.
- A binary XCFramework can't be depended on directly by multiple sibling
  SPM packages without repeating the relative path everywhere. Standard
  fix: wrap it once in a thin `SharedKit` package
  (`.binaryTarget` + `@_exported import TrailMetricsShared`), and have
  every feature package depend on `SharedKit` instead of the framework
  directly. The app target also drops its direct XCFramework link in
  favor of depending only on `SharedKit`.
- When creating a new local SPM package, choose "Don't add to any project
  or workspace" in the save dialog, then manually wire it via
  File → Add Package Dependencies → Add Local... This avoids Xcode
  silently doing unexpected project wiring.
- Xcode Run Script build phases run every build unless given at least one
  Output File — this is a cosmetic warning check only, unrelated to
  whether the script's own internal logic actually skips work.
- Xcode's User Script Sandboxing (`ENABLE_USER_SCRIPT_SANDBOXING`) blocks
  Gradle/Kotlin-Native subprocess and file operations invoked from a Run
  Script phase. Must be set to NO in Build Settings for any KMP project
  that triggers Gradle from an Xcode build phase.
- Practical incremental-build script pattern: hash `mtime + path` of all
  `.kt`/`.kts` files across the KMP source dirs (`domain/src data/src
  shared/src`), compare to a stamp file, only invoke Gradle when the hash
  changed. Plain Xcode Input/Output File tracking is unreliable here
  because it only watches direct folder mtimes, not deep recursive
  content changes.

### Reference: Incremental KMP rebuild script (Xcode Run Script Phase)

Location: TrailMetrics target → Build Phases → "Build KMP Shared Framework"
(placed as the FIRST build phase, before Sources/Frameworks/Resources).
Output Files: `$(SRCROOT)/../shared/build/.xcode_kmp_stamp` (silences
Xcode's "no outputs" warning; the real skip logic lives in the script).

```bash
set -e
cd "${SRCROOT}/.."

STAMP_FILE="shared/build/.xcode_kmp_stamp"
SOURCE_DIRS="domain/src data/src shared/src"

CURRENT_HASH=$(find $SOURCE_DIRS -type f \( -name "*.kt" -o -name "*.kts" \) -exec stat -f "%m %N" {} \; | sort | shasum | awk '{print $1}')

if [ -f "$STAMP_FILE" ] && [ "$(cat "$STAMP_FILE")" == "$CURRENT_HASH" ]; then
  echo "KMP shared framework is up to date, skipping Gradle build."
else
  echo "KMP source changed, rebuilding shared framework..."
  ./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework
  echo "$CURRENT_HASH" > "$STAMP_FILE"
fi
```

Also required in Build Settings: `ENABLE_USER_SCRIPT_SANDBOXING = NO`,
otherwise the Gradle invocation fails with
`Execution failed for task ':shared:checkSandboxAndWriteProtection'`.

---

## Phase I — Enforcement (allWarningsAsErrors, Detekt, SwiftLint) and CI

- `allWarningsAsErrors = true`, applied project-wide via `subprojects { }`
  in the root `build.gradle.kts`, needs three separate `plugins.withId(...)`
  blocks (`org.jetbrains.kotlin.jvm`, `org.jetbrains.kotlin.android`,
  `org.jetbrains.kotlin.multiplatform`) configuring the matching
  `Kotlin*ProjectExtension` — a mixed Android+KMP module graph has all
  three plugin types present across different modules, and there's no
  single extension type that covers all of them.
- Turning this on immediately surfaces every pre-existing warning as a
  build failure. In this project that meant: unnecessary `as` casts in
  `domain`'s test suite (Kotlin's smart-cast already narrowed the type;
  the explicit cast was a leftover from before `assertIs<T>()` was
  introduced), and the `expect`/`actual class` Beta warning in `data`
  (silenced with the compiler flag below).
- The `-Xexpect-actual-classes` flag itself needs to be added via
  `compileTaskProvider.configure { compilerOptions { ... } }`, not the
  older `compilerOptions.configure { }` on the `KotlinCompilation`
  directly — the latter is deprecated in current Kotlin Gradle plugin
  versions. Ironically, the first fix for a warning caused by turning on
  `allWarningsAsErrors` was itself a deprecated API needing replacement.
- `ActivityHistoryRepositoryImplTest` (in `data`'s `commonTest`) fails with
  `UnsatisfiedLinkError` / `NoClassDefFoundError` on `BundledSQLiteDriver`
  when run under `androidHostTest` (Robolectric) — not because the test
  itself uses Robolectric, but because Robolectric's `SandboxClassLoader`
  isolation for *other* tests in the same JVM process (specifically
  `UserProfileRepositoryImplTest`) interferes with the native SQLite
  binary's JNI loading, which is a once-per-process operation. Fixed by
  excluding this test class specifically from `testAndroidHostTest` via
  `tasks.withType<Test>().configureEach { if (name == "testAndroidHostTest") { filter { excludeTestsMatching(...) } } }`
  — it still runs correctly under `commonTest`/`iosSimulatorArm64Test`,
  which is its actual coverage source.
- `tasks.named("taskName")` is eager and will throw
  `UnknownTaskException` if the named task hasn't been created yet at the
  point the build script evaluates that line (task creation order in a
  KMP module isn't something to rely on). `tasks.withType<Test>().configureEach { }`
  with an `if (name == ...)` check inside is the lazy, order-independent
  equivalent — prefer it whenever conditionally configuring a task that a
  plugin creates.
- KSP + Android Lint have a known task-ordering gap: `lintAnalyzeAndroidHostTest`
  and `generateAndroidHostTestLintModel` read KSP's generated sources
  without Gradle being told about the dependency, causing "implicit
  dependency" validation failures on a full `./gradlew build`. Fixed with
  an `afterEvaluate` block adding `mustRunAfter("kspAndroidHostTest")` to
  the matching lint tasks. This is unrelated to any change made in this
  project — it surfaces the first time a full `build` (not just `assemble`
  or `test`) is run against a KMP module using both KSP and Android Lint.
- SwiftLint needs no separate installation step on GitHub Actions'
  `macos-latest` runners — it ships preinstalled, same as Xcode and
  fastlane.
- iOS CI (`xcodebuild build -destination "generic/platform=iOS Simulator"`)
  needs the XCFramework built *before* `xcodebuild` runs, via an explicit
  `./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework` step —
  the Xcode project's own Run Script build phase for this exists for local
  development inside Xcode.app, but isn't guaranteed to behave identically
  when `xcodebuild` is invoked directly from a CI shell in a fresh
  checkout with no prior Gradle daemon state.
