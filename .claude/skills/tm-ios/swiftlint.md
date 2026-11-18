# SwiftLint (CI-enforced, `--strict`)

Moved word for word from `SKILL.md`: the section "SwiftLint (CI-enforced, `--strict`)". The rules are unchanged; they are still cited as `tm-ios`, "SwiftLint".

## SwiftLint (CI-enforced, `--strict`)

Config: `iosApp/.swiftlint.yml`. Run it from `iosApp/` with `swiftlint lint --strict`. It
runs in `scripts/pre-push-check.sh` (whenever a file other than markdown under `iosApp/`,
`domain/`, `data/`, `core/`, `shared/` or `shared-uitest/` changed, or a root Gradle file: `build.gradle.kts`,
`settings.gradle.kts`, `gradle.properties`, `gradle/libs.versions.toml`, or a file that runs the
Gradle build: `gradlew`, `gradle/wrapper/gradle-wrapper.jar`, `gradle/wrapper/gradle-wrapper.properties`,
`gradle/gradle-daemon-jvm.properties`, or `scripts/build-kmp-framework.sh`) and in CI's `ios-build` job, followed by an `xcodebuild` simulator build.

- One SwiftLint version everywhere: `config/swiftlint.pin` (version and the sha256 of the release's
  `portable_swiftlint.zip`). CI installs exactly it (`scripts/swiftlint-pin.sh --install`) and the gate's step
  `swiftlint version` fails when the `swiftlint` on PATH is another version (`scripts/swiftlint-pin.sh --check`);
  `brew install swiftlint` gives only the newest release, so install the pin into a directory and put it first on PATH.
  A new version is a change of that file with the lint run on it. The opt-in rules `weak_delegate`,
  `discarded_notification_center_observer`, `unhandled_throwing_task`, `unowned_variable_capture` and
  `implicitly_unwrapped_optional` are on. `async_without_await` and the analyzer rules (`swiftlint analyze`, which
  needs a compile log) are not; the reasons are in `iosApp/.swiftlint.yml` and the board record `swiftlint-analyzer-rules`.
- `--strict` promotes every warning to a failure. The `warning` thresholds are the real
  limits: line length 120, function body 60 lines, type body 300 lines, cyclomatic
  complexity 15.
- `force_unwrapping`, `force_cast` and `force_try` are errors. Restructure with
  `guard let`/`if let`, `as?` with explicit `else` handling, or `do`/`catch`.
- Opt-in rules on top of the defaults: `force_unwrapping`, `unused_import`, `explicit_init`,
  `closure_spacing`, `empty_count` (use `.isEmpty`), `fatal_error_message`.
- Custom rule `optional_try` (error): a regex for `try?`, not matched inside comments and
  string literals (`excluded_match_kinds`); `try` and `try!` are not its business (`force_try`
  covers `try!`). Handle the error with `do`/`catch`; a deliberate `try?` needs the
  `swiftlint:disable:next optional_try - <reason>` comment on the line above, allowed only for a
  best-effort side effect whose failure the user can't act on, the reason saying why the error can
  be dropped there. The only two in production code are `SnapshotFileDeleter.deleteBestEffort` (an orphaned image
  file after the record is gone) and `ActivityKitLiveActivityClient`'s `Activity.request` (Live
  Activities can be turned off); the test helper `waitUntil` (TestSupport)
  carries the same comment; no other `try?` is left
  under `iosApp/`. SwiftLint does not check that a reason is there or true: review does. An invalid `excluded_match_kinds` name only prints "Invalid configuration for
  'optional_try' rule" and turns the rule off, without failing `--strict`; `scripts/check-optional-try.sh --self-test`
  (in the gate's iOS steps and CI's `ios-build`) lints fixtures with the committed config, fails on that message,
  and shows the rule silently off on a config with an unknown kind.
- Custom rules `localized_text_without_bundle` and `literal_text_in_view_initializer` (error):
  see "Strings". They match source text with `included`/`excluded` path regexes, so a new
  production source folder outside `Packages/*/Sources`, the files directly in `iosApp/TrailMetrics/`
  and `iosApp/TrackingWidget/` needs its path added to both rules.
- Don't add `// swiftlint:disable` comments and don't edit `.swiftlint.yml` to make a
  violation pass. Refactor instead, or ask if the rule genuinely doesn't fit. A suppression
  needs explicit human approval and a stated reason. Every existing one has the form
  `// swiftlint:disable:next <rule> - <reason>`.
