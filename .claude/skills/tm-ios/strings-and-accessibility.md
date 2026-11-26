# Strings, accessibility, numbers, units and durations

Moved word for word from `SKILL.md`: the sections "Strings", "Accessibility" and "Numbers, units and durations". The rules are unchanged; they are still cited as `tm-ios`, "Strings", "Accessibility" and "Numbers, units and durations".

## Strings

This is the iOS side of the project-wide rule (`tm-kmp-shared`, "User-visible text"): no text the user
reads is written in code, and a text that comes from Kotlin arrives as a typed value that iOS turns
into text from its own catalog, never as a finished Kotlin string shown verbatim.

No user-visible text is a hardcoded string. Every text the user reads (labels, button titles,
navigation and tab titles, alerts, empty and error states, accessibility labels and hints, map
marker titles) comes from a String Catalog, `Localizable.xcstrings`, next to the sources of the
package that shows it (`iosApp/Packages/<Feature>/Sources/<Feature>/`), of the app target
(`iosApp/TrailMetrics/`) or of the widget extension (`iosApp/TrackingWidget/`). Language: English
for now (`defaultLocalization: "en"`). Adding one means adding its column to the catalogs,
no code change.

- **Bundle.** Inside an SPM package SwiftUI looks in the main bundle unless told otherwise, so a
  literal without the package bundle is silently not localized. Only `Text` takes `bundle:`;
  every other view takes its text as a `Text`:

  ```swift
  Text("Generate Route", bundle: .module)
  Button { save() } label: { Text("Save", bundle: .module) }
  Label { Text("Reset", bundle: .module) } icon: { Image(systemName: "arrow.clockwise") }
  TextField(text: $weightInput) { Text("Weight (kg)", bundle: .module) }
  .navigationTitle(Text("User Profile", bundle: .module))
  .alert(Text("Error", bundle: .module), isPresented: $isShown) { ... }
  ```

  In the app and widget targets the bundle is the main one: `bundle: .main`.
- **Outside a View** (ViewModel, error and formatter texts, `GMSMarker.title`) a `String` shown
  with `Text(string)` is verbatim and never localized, so make the string with
  `String(localized: "key", bundle: .module)`. Use a computed property, not a `static let`, so it
  follows the language at the time it is read. A child view that shows a label takes a `Text`
  (`HistoryMetricCell(label: Text("metric_distance", bundle: .module), ...)`), not a `String`.
  The Live Activity's `activityType` stays an English identifier that the widget localizes with
  its own catalog (`Text(LocalizedStringKey(activityType), bundle: .main)`).
- **Keys.** The English text is the key (`Text("Generate Route", ...)`). A text used in several
  places of a package, or one that is formatted, gets a descriptive snake_case key
  (`delete_activity_title`, `general_error_message`) whose English value is in the catalog.
  Interpolated texts use format arguments in the key, never `+`. A new key is added to the
  catalog in the same change, with an `en` string unit.
- **Not user-visible text, leave as is:** `accessibilityIdentifier`, log messages, `systemName:`
  symbols, URL schemes and notification names, test code and fakes, `UITestSupport`, previews'
  sample data.
- **Enforced** by two SwiftLint custom rules in `iosApp/.swiftlint.yml` (see "SwiftLint", `swiftlint.md`):
  `localized_text_without_bundle` (a `Text("literal")` without `bundle:`) and
  `literal_text_in_view_initializer` (a string literal as the first argument of `Button`, `Label`,
  `TextField`, `.navigationTitle`, `.alert`, `.accessibilityLabel` and similar). Both cover
  production sources of the packages, the app target and the widget only. They cannot see a
  `String` that is shown later (`Text(message)`), so review checks that those strings are made
  with `String(localized:bundle:)` (`tm-pr-review`). Self-test of the rules:
  `scripts/check-localized-strings.sh --self-test` (in the gate's iOS steps).
- A package's tests resolve one of its keys through `Bundle.module` with
  `LocalizationAssertions.assertResolves` (TestSupport); copy `HistoryTests/LocalizationTests.swift`
  for a new package (it needs `@testable import`).
- Known limits, not fixed here: the texts that `MetricsFormatter` (Kotlin) returns, with their
  unit words, and the widget's own number formatting are hardcoded (board:
  `shared-metrics-formatter-user-visible-strings`, `ios-hardcoded-number-formatting`).

## Accessibility

- Every control that shows only an icon has an `accessibilityLabel` made with `String(localized:)`
  or a `Text` (see "Strings"), and the same for a state it shows only by color or shape.
- A cell that shows a value and its label (the metric cells) is one element:
  `.accessibilityElement(children: .combine)`, so VoiceOver reads "label, value" once.
- Sizes follow the user's text size: fonts are text styles; a fixed size that must grow
  uses `@ScaledMetric`. An animation checks `@Environment(\.accessibilityReduceMotion)`.
- Decorative images are `.accessibilityHidden(true)`.
- The map is a UIKit view ("Wrapping a UIKit view (the maps)", `uikit-and-concurrency.md`): give its `UIViewRepresentable` an accessibility label and
  describe the result in text elsewhere on the screen; a polyline is not readable by VoiceOver.
- Camera moves on a map follow Reduce Motion: a jump when `UIAccessibility.isReduceMotionEnabled`, an
  animation otherwise (`GMSMapView+ReduceMotion.swift` in `Route`; the tracking map has the one-line copy).
- Enforced: `AccessibilityAuditUITests` runs Xcode's accessibility audit (element descriptions, hit regions)
  on Route, History, Details and Tracking in the gate's UI tests; a new screen adds its case there. Reduce
  Motion, the scaled sizes and the widget have no automated check: reviewer only. Violation: `important`.


## Numbers, units and durations

- User-visible numbers, units and durations are formatted per platform and locale. The direction
  (owner decision) is not to format them in the Kotlin `domain`; moving the existing formatting out of
  Kotlin is a refactor of its own and is not scheduled (the two board records in "Strings").
- New Swift code does not use `String(format:)` for a number the user reads. Use the format styles
  (`value.formatted(...)`, `Measurement` with `.formatted(.measurement(...))`, `Duration.formatted`,
  `Date.FormatStyle`), which follow the locale, or `Text(value, format:)`.
- Existing exceptions, not to copy: `TrackingWidget/TrackingLiveActivity.swift` formats
  distance, pace and elapsed time with `String(format:)` (board: `ios-hardcoded-number-formatting`).
