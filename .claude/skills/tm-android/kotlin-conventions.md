# Kotlin naming, deprecation, dead code and Detekt

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the sections "Naming (Kotlin)", "No deprecated APIs (Kotlin)", "No dead code" and "Detekt (CI-enforced, `maxIssues: 0`)". The rules are unchanged; they are still cited as `tm-android`, "Naming (Kotlin)", "No deprecated APIs (Kotlin)", "No dead code" and "Detekt".

## Naming (Kotlin)

- Gradle modules: lowercase, hyphenated (`feature-history`). Packages: lowercase dot
  segments, no underscores (`dev.roozbahani.trailmetrics.feature.history`, never
  `featurehistory` or `feature_history`). Detekt's `PackageNaming` only rejects underscores
  and uppercase-leading segments, so the rest is review-enforced.
- Classes/interfaces/objects `PascalCase`; interfaces carry no `I` prefix
  (`ActivityHistoryRepository`, not `IActivityHistoryRepository`). Functions/properties
  `camelCase`. `@Composable` functions are `PascalCase` (Detekt's `FunctionNaming` ignores
  `@Composable`).
- Booleans read as questions: `isLoading`, `canStart`, `hasReachedDestination`,
  `showProfileSheet` for visibility flags. Never a bare noun. (Detekt's
  `BooleanPropertyNaming` is off, so this one is review-enforced.)
- Per-feature types: see the MVI naming in `SKILL.md` ("Presentation layer — MVI (target shape)"). Koin modules: `<feature>Module` /
  `<feature>UiModule` in `di/<Feature>Module.kt`.
- Test names are backtick sentences (`` `saves activity with recalculated calories`() ``),
  never `test1`. See `tm-testing`. The exception is `androidTest`, where names are camelCase (a name
  with a space does not dex at `minSdk` 26).

## No deprecated APIs (Kotlin)

`CLAUDE.md` states the rule (never call a deprecated API); the Kotlin specifics:
- Use the documented replacement (for example `Icons.AutoMirrored.Filled.DirectionsRun`, not
  `Icons.Filled.DirectionsRun`), including for AndroidX/Compose/Material APIs deprecated in the
  current BOM.
- `allWarningsAsErrors = true` is set for every Kotlin module: the root `build.gradle.kts` hooks
  `plugins.withId("com.android.application")` / `("com.android.library")` for `androidApp/*`
  (AGP 9 built-in Kotlin, so `org.jetbrains.kotlin.android` is never applied) and the
  `org.jetbrains.kotlin.multiplatform` block for KMP modules. Any compiler warning, including a
  deprecation or an unacknowledged `@RequiresOptIn`, fails the build.
- Experimental APIs (`@RequiresOptIn`, e.g. maps-compose's `MapsComposeExperimentalApi`) also
  warn. With no stable alternative, opt in as narrowly as possible, at the call expression or the
  smallest enclosing declaration, with a comment saying why (see `MapEffect` in
  `TrackingScreen.kt`). Never opt in module-wide via `optIn` compiler options.
- A genuinely unavoidable deprecation (a third-party library with no replacement yet): suppress it
  narrowly at the call site with `@Suppress("DEPRECATION")` and a comment stating why, only with
  human approval, never at file or module level.
- Don't mark your own APIs `@Deprecated` to phase them out. Update the callers and delete the
  old API in the same change.

## No dead code

- No commented-out code in a commit. Git history is the backup.
- No unused private functions, properties, classes or parameters left behind after a
  refactor. Detekt's `UnusedPrivateMember`/`UnusedPrivateProperty`/`UnusedPrivateClass`/
  `UnusedParameter` catch the private ones. Unused `internal`/`public` code and unused
  imports (`UnusedImports` is off) are not caught, so check them yourself.
- Explanatory comments on *why* are welcome (see `MainActivity`'s `stopTrackingRequested`
  and `trackingUiModule`'s `CalorieCalculator` note). Commented-out code is not.


## Detekt (CI-enforced, `maxIssues: 0`)

Config: `config/detekt/detekt.yml`, applied to every subproject by the root
`build.gradle.kts` with `buildUponDefaultConfig = true` and `autoCorrect = true`. Run it
with `./gradlew detekt detektTyped`: `detekt` is the plain run, `detektTyped` the run with type
resolution (the rules that need it, and which of them fire: `tm-robustness`, "Mechanical rules").
Both are part of the local pre-push gate (`scripts/pre-push-check.sh`) and CI.

KMP modules (`domain`, `data`, `core`, `shared`, `shared-uitest`) have no `src/main`, which
is all the plain `detekt` task reads, so the root build points it at every `src/*` source set
(it was NO-SOURCE there before).

- Forbidden: `println`/`print` (use a logger; `ForbiddenMethodCall` cannot resolve them, so
  `scripts/check-no-println.sh` fails the gate and CI on a bare call in production code) and any
  `kotlinx.coroutines.GlobalScope` import (`ForbiddenImport`, use `viewModelScope` or an injected scoped
  `CoroutineScope`).
- Thresholds: `LongMethod` 60 lines, `CyclomaticComplexMethod` 15 (both ignore
  `@Composable` functions but apply everywhere else), `TooManyFunctions` 12 per class,
  `LongParameterList` 7 for functions and constructors (`TrackingSessionManager.kt` and
  `TrackingViewModel.kt` are excluded; a class growing too many parameters is a signal to look at
  its responsibilities, not to extend the exclude list). Default `MaxLineLength` is 120. `MagicNumber` and `ReturnCount` are off.
- `!!` is rejected by detekt's `UnsafeCallOnNullableType`, which is on by default, and in review.
  Use `checkNotNull(x) { "why" }`, or restructure so the nullable type never reaches that point.
- Don't add excludes to `config/detekt/detekt.yml` and don't add `@Suppress` to make a
  violation pass. Refactor instead, or ask if the rule genuinely doesn't fit. Any
  suppression needs explicit human approval and a comment with the reason, on its own line
  directly above the annotation.
