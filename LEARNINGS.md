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

## [Next entry goes here — Phase B: Ktor engine swap / Room KMP driver / etc.]
