# Build integration, build configurations and schemes

Moved word for word from `SKILL.md`: the sections "Build integration (XCFramework pre-action + Run Script)" and "Build configurations and schemes". The rules are unchanged; they are still cited as `tm-ios`, "Build integration" and "Build configurations and schemes".

## Build integration (XCFramework pre-action + Run Script)

- `scripts/build-kmp-framework.sh` is the one place that decides whether the shared
  XCFramework needs Gradle. It hashes the **content** of every `*.kt`/`*.kts` under
  `domain/src data/src core/src shared/src shared-uitest/src`, plus `settings.gradle.kts`, the root
  `build.gradle.kts`, `gradle.properties`, `gradle/libs.versions.toml`,
  `gradle/wrapper/gradle-wrapper.properties`, `domain|data|core|shared|shared-uitest/build.gradle.kts` and
  `local.properties` (if present; BuildKonfig compiles its API key into the framework). It
  compares the variant and that hash against `shared/build/.xcode_kmp_stamp` and runs
  `./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework` when the hash or the variant
  changed or the XCFramework is missing. With `--variant uitest` it also builds the test-only
  variant of `shared-uitest`, checks its API against production's (`scripts/check-variant-api.sh`)
  and copies it over the same
  debug path (ADR-002, "Amendment"). The stamp is deleted before Gradle and written only after
  it succeeds. `SharedKit/Package.swift` points at the **debug** XCFramework output.
  Deliberately not hashed: `gradlew`, `gradle/wrapper/gradle-wrapper.jar` and
  `gradle/gradle-daemon-jvm.properties`. `gradle-wrapper.properties` names the Gradle version;
  the first two only launch that version and the third only selects the JVM that runs the
  Gradle daemon, so none of them is expected to change the Kotlin/Native output. The gate's iOS
  filter (`IOS_PATHS`) still lists all three, so its iOS steps run when the build tooling
  changes. On a machine whose stamp matches, a diff of only these files makes the gate's
  "KMP XCFramework" step print "up to date" and skip Gradle. That is intended; if a change to
  one of them ever does change the framework, delete the stamp to force the rebuild.
- Callers:
  - The shared `TrailMetrics` scheme
    (`TrailMetrics.xcodeproj/xcshareddata/xcschemes/TrailMetrics.xcscheme`) runs it as a
    Build pre-action. That is what makes a single build pick up a Kotlin change: Xcode copies
    the XCFramework (`ProcessXCFramework`) and compiles the Swift packages *before* any of
    the app target's phases run. The pre-action output, including Gradle errors, is in the
    build log, and a failing pre-action fails the build.
  - The shared `TrailMetricsUITests` scheme has the same Build pre-action (see "Build
    configurations and schemes").
  - The `TrailMetrics` target's "Build KMP Shared Framework" Run Script phase (first phase,
    `alwaysOutOfDate = 1`, output `.xcode_kmp_stamp`) runs it with `--build-phase` as a
    safety net. If the pre-action didn't run, it rebuilds and then fails the build with
    "build again" rather than link the stale copy. Don't declare the XCFramework as a phase
    output: Xcode reports "Cycle inside TrailMetrics".
  - `scripts/pre-push-check.sh` runs it before the iOS build, then
    `scripts/check-production-framework.sh` on the production framework, and runs it with
    `--variant uitest` right before the package tests (see below).
  - CI's `ios-build` job runs it in its "Build KMP Shared Framework" step, before the iOS
    simulator tests and the `xcodebuild` build, runs `scripts/check-production-framework.sh`
    after it, and builds the variant in the step "Build test-only framework variant" before
    "Run iOS package tests", which also runs the variant's API check (`scripts/check-variant-api.sh`).
    The iOS UI tests are not built or run in CI: the gate's iOS UI step (`scripts/ios-ui-tests.sh`) builds the
    variant and the UI-test target and runs them.
- The Swift package tests link the **test-only variant**, not production: the Kotlin test
  support they need (`SwiftTestFlow`, `SwiftFailingTestFlow`, `SwiftTestScope`, `SwiftTestResult`, `SwiftTestRepositories`,
  package `dev.roozbahani.trailmetrics.uitest.testsupport`) is in `shared-uitest`. The production
  framework contains none of it; `scripts/check-production-framework.sh` (gate and `ios-build`)
  fails when any of those names, or the `testsupport` package name, is in its binary. The
  variant's API check (`scripts/check-variant-api.sh`) lists these five classes with the UI-test
  seam as the only names allowed in the variant alone.
- A per-user `xcuserdata/.../TrailMetrics.xcscheme` with the same name shadows the shared
  scheme and has no pre-action. If every Kotlin change ends in the "build again" error,
  delete the per-user copy.
- `xcodebuild test` inside a package directory (`iosApp/Packages/<Name>`) uses the package's
  own scheme. It runs neither the pre-action nor the phase, so run
  `scripts/build-kmp-framework.sh --variant uitest` first (the gate does): the package tests
  need the test-only variant. A normal build afterwards rebuilds production.
- Building the app from the command line (the command is CI's `ios-build` "Build iOS app"
  step; the gate runs the same one):

  ```bash
  cd iosApp
  xcodebuild build -project TrailMetrics.xcodeproj -scheme TrailMetrics \
    -destination "generic/platform=iOS Simulator" -skipMacroValidation \
    ARCHS=arm64 EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO
  ```

  Without the architecture flags a build on clean derived data fails (the XCFramework has no
  x86_64 slice). The gate also pipes the output through `scripts/filter-xcode-log.sh`, which
  hides the exported build settings (they include the Maps key) from the log.
- The app target sets `ENABLE_USER_SCRIPT_SANDBOXING = NO` in its three configurations (the project level has
  `YES`) because the "Build KMP Shared Framework" phase writes `shared/build/.xcode_kmp_stamp` and can run Gradle,
  which a sandboxed script phase cannot do. The pre-action is a scheme action, not a build phase.
- Never run `integrateEmbedAndSign` or `integrateLinkagePackage` (the Kotlin Gradle plugin's tasks that rewrite an
  Xcode project for `embedAndSignAppleFrameworkForXcode` or SwiftPM import) on this project: they add a second
  integration next to the pre-action and the phase. Enforced: reviewer only. Violation: `blocking`.
- Never disable, reorder or bypass the pre-action or the phase, and keep the shell logic in
  the script, not inline in the scheme or the project file.
- Unexpected "missing/stale symbol from `TrailMetricsShared`": look in the build log for the
  "Build KMP Shared Framework" pre-action and phase lines
  ("rebuilding shared framework..." / "up to date, skipping Gradle build"). Deleting the stamp
  forces the next build to run Gradle.
- `./gradlew clean` wipes the XCFramework; the next Xcode build has to regenerate it.

## Build configurations and schemes

- The project has three build configurations: `Debug`, `Release` and `Debug-UITest`.
  `Debug-UITest` is a copy of `Debug` in every configuration list (the project, `TrailMetrics`,
  `TrackingWidgetExtension`, `TrailMetricsUITests`); the only difference is at the project level,
  where `SWIFT_ACTIVE_COMPILATION_CONDITIONS` is `DEBUG UITEST_SEAM $(inherited)`. So the project's
  targets see `UITEST_SEAM` and `DEBUG`; the Swift packages see `DEBUG` only. A build setting
  added to or changed in `Debug` belongs in `Debug-UITest` too.
- Keep `Debug` in the name of a configuration that should build like Debug: Xcode picks the
  SwiftPM packages' debug or release build from the name (seen with `xcodebuild`: a
  configuration named `UITest` built the packages as Release, `-O`, whole-module, no `DEBUG`).
- Two shared schemes build the app:
  - `TrailMetrics`, the normal scheme: Run, Test and Analyze on `Debug`, Profile and Archive on
    `Release`, and no testables. It links the production framework. CI's "Build iOS app" step
    and the gate build it.
  - `TrailMetricsUITests`, the UI-test scheme: the same Build pre-action, Test and Launch on
    `Debug-UITest`, the `TrailMetricsUITests` testables and that target's build-for-testing
    entry. It links the test-only variant of the framework (built by `shared-uitest`, ADR-002
    "Amendment").
- How the variant is picked: `scripts/build-kmp-framework.sh` builds the variant when Xcode's
  `CONFIGURATION` is `Debug-UITest` (the pre-action and the `--build-phase` safety net alike),
  and with `--variant uitest` when it is called outside Xcode; otherwise it builds production.
  Both go to the same debug path, which `SharedKit/Package.swift` links in every configuration.
- Running the UI tests locally (a concrete simulator; the pre-action builds the variant):

  ```bash
  cd iosApp
  xcodebuild test -project TrailMetrics.xcodeproj -scheme TrailMetricsUITests \
    -destination "platform=iOS Simulator,id=<simulator id>" -skipMacroValidation \
    ARCHS=arm64 EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
    2>&1 | ../scripts/filter-xcode-log.sh
  ```

  Add `-only-testing:TrailMetricsUITests/<TestClass>` for one class. Without the architecture
  flags a build on clean derived data fails (the XCFramework has no x86_64 slice). The filter
  hides the exported build settings, which carry the Maps key, from the log.
- After a UI-test run the debug path holds the variant until the next normal build. That build
  rebuilds production on its own: the stamp records the variant, so its pre-action prints
  "KMP source or framework variant changed, rebuilding shared framework (production)..." and
  replaces the variant before anything links it.
