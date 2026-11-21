# Build integration, KMP module build setup, Kotlin/Native build cost

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the sections "Build integration", "KMP module build setup" and "Kotlin/Native build cost". The rules are unchanged; they are still cited as `tm-kmp-shared`, "Build integration", "KMP module build setup" and "Kotlin/Native build cost".

## Build integration

After changing `domain`, `data`, `core` or `shared`, iOS needs a rebuilt XCFramework.
`scripts/build-kmp-framework.sh` does this automatically (hash of the sources of the four
modules and `shared-uitest`, the Gradle build files, and which variant is in place: production,
or the UI-test variant of `shared-uitest` for `--variant uitest` and for the `Debug-UITest`
configuration, which selects the variant). The shared `TrailMetrics` scheme's Build pre-action and the
"Build KMP Shared Framework" phase run it on every Xcode build, and so does the gate. Do not
bypass it. Run the script yourself with `--variant uitest` before `xcodebuild test` inside an
iOS package: the package tests link the test-only variant (details in `tm-ios`).

## KMP module build setup

The four KMP modules share one build shape. `domain/build.gradle.kts` is the template: copy its
structure for a new module and take the iOS targets and KSP lines from `data`.

- Plugins: `org.jetbrains.kotlin.multiplatform` and `com.android.kotlin.multiplatform.library` (AGP
  9.2.1). Never `com.android.library` or `com.android.application` next to the KMP plugin.
- Android settings sit in `kotlin { android { namespace; compileSdk; minSdk; compilerOptions { jvmTarget } } }`.
  Write them there, not in a top-level `android {}` block and not in `androidTarget {}`.
- `withHostTestBuilder {}.configure {}` in that block creates the `androidHostTest` source set. Its
  dependencies go in `getByName("androidHostTest") { dependencies { ... } }` (see `data`); `commonTest`
  runs on the Android host and on the iOS simulator.
- A new module declares `iosArm64()` and `iosSimulatorArm64()` and no `iosX64()`. Room 3.0.2 publishes no
  iosX64 artifact (`LEARNINGS.md`). The Room processor goes to each target on its own, as in `data`:
  `add("kspAndroid", ...)`, `add("kspIosArm64", ...)`, `add("kspIosSimulatorArm64", ...)`, never a broad `ksp(...)`.
- Versions come from `libs.versions.toml`, and a constant that used to be `BuildConfig` comes from BuildKonfig
  (`data`): these modules have no `BuildConfig` class.
- Enforced: reviewer only. Violation: `important`.

## Kotlin/Native build cost

Measured on 2026-11-17 (Apple M4, 16 GB, Kotlin 2.4.10, warm `~/.konan` and Gradle caches, fresh clone of
`main` at `ed7943f`, `scripts/heavy-run.sh ./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework
:shared:linkReleaseFrameworkIosArm64 :domain:linkDebugTestIosX64`): 66 s wall time.

- A debug framework link takes about 11 s per slice, with about 6 s of compile and 4 s of KSP before it; the
  release link of one slice takes 52 s, about 4.7 times the debug link; `:domain:linkDebugTestIosX64` takes 19 s.
- Static archive sizes: 70.5 MB per debug slice, 22.6 MB for release arm64; the debug XCFramework is 147 MB.
  The Swift header `TrailMetricsShared.h` has 13,691 lines and 393 Objective-C types, about 190 of them from
  Ktor, kotlinx, Koin, Room and the `data` internals.
- Since `shared` and `shared-uitest` stopped exporting `:data`, the same header has 6,263 lines and 212 declarations
  (`@interface` and `@protocol` lines; the 393 above counts unique types, the same count gives 402 before), and the debug
  XCFramework is 140 MB instead of 148 MB. A Swift test that needs a real `data` object takes it from a factory in
  `shared-uitest` (`SwiftTestRepositories`). Never export `:data` from a framework again: its Ktor, kotlinx, Koin and Room
  types are not API for Swift. Enforced: reviewer only. Violation: `important`.
- CI's `ios-build` job caches `~/.konan`, keyed on the Kotlin version of the version catalog (a bump starts a new cache). On a miss the
  dependencies are downloaded and unpacked (their cost was not measured) and the framework link took about 116 s; with the cache the
  link takes about 9 s, and the iOS job was 4 min 54 s to 8 min 26 s shorter across three miss/hit pairs (hits 10 min 38 s to
  12 min 35 s, misses 16 min 51 s to 19 min 4 s; runner type: 3 CPUs, 7 GiB). The Kotlin/Native steps are about 2.3 to 3.4 minutes of that;
  the rest, mostly the Swift package tests, is not isolated. Xcode's DerivedData is not cached (not isolated; not adopted for the
  risk of a stale build product).
- The `~/.konan` cache of 2026-11-17 (PR #330, closed) was judged by the download it saves (about 8 s) against a restore of 22 to
  24 s, and by step totals that vary by 144 s between runs of identical code; the saving is in the link, not the download, and
  a comparison needs two attempts of the same commit (PR #372).
- The Gradle daemon in CI runs on the runner's Temurin 21 (21.0.13 on 2026-11-17); only the launcher is JDK 17, the
  one `setup-java` installs.
- A change to the build (targets, exports, caches, flags) is measured: run the real command twice before and
  twice after, on the same machine and state, under `scripts/heavy-run.sh`, and put both numbers in the PR
  (the first run fills caches). Enforced: reviewer only. Violation: `important`.
- A faster local loop changes nothing that CI or a Release build produces. Enforced: reviewer only. Violation: `blocking`.
- Open work is on the board: `release-build-links-debug-xcframework`, `ios-simulator-only-framework-slice`,
  `swift-api-header-dump-in-gate`, `ios-ci-package-tests-duration`.
- Revisit when: Room publishes an iosX64 artifact, or Intel simulators are wanted again; the no-iosX64 rule for new
  modules then changes.
