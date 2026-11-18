# Koin registration, module and Gradle conventions

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the sections "Koin" and "Module / Gradle conventions". The rules are unchanged; they are still cited as `tm-android`, "Koin" and "Module / Gradle conventions".

## Koin

Match `TrailMetricsApplication.kt`'s existing style exactly:
- One `val <x>Module = module { ... }` per feature (`trackingUiModule`, `routeModule`,
  `historyUiModule`), in that feature's `di/` subpackage
  (`feature/tracking/di/TrackingUiModule.kt`), registered in `initKoin { modules(...) }`
  inside `TrailMetricsApplication.onCreate()`
  (`androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/`). `shared`'s `initKoin()`
  only registers cross-platform modules; Compose-UI modules must be passed in here.
- Prefer `viewModelOf(::MyViewModel)` / `singleOf(::Impl)` constructor-reference form.
  Only fall back to the lambda form (`viewModel { ... }`) when you need a factory
  method, a qualifier, runtime parameters (`params.get()`), or post-construction setup.
  Today every module uses the lambda form, including `HistoryViewModel` and
  `RouteViewModel`, which have no parameters. Don't take that as the pattern for new code.
- Constructor injection only, resolved with `get()`. No field injection (`by inject()`) and
  no `KoinComponent` in application code. `KoinComponent` is acceptable only inside
  `shared`'s `KoinHelper` bridge for iOS. Existing exception: `MainActivity` field-injects
  `TrackingSessionManager` with `by inject()`. Don't copy it.
- Cross-platform bindings (anything iOS also needs via `KoinHelper`) go in `shared`/
  `data`, not here — see `tm-kmp-shared`.
- Always inject ViewModels with `koinViewModel()` in the Root composable. Never pass a
  ViewModel down the composable tree.


## Module / Gradle conventions

New feature modules follow the existing `androidApp/feature-tracking`-style layout:
`com.android.library` + `org.jetbrains.kotlin.plugin.compose` plugins (Kotlin comes from
AGP 9's built-in support; there is no `kotlin-android` plugin), `compileSdk` via
`release(37) { minorApiLevel = 1 }`, `minSdk 26`, Java 11 source/target compatibility,
`buildFeatures { compose = true }`, dependencies on `:domain`, `:core`,
`:androidApp:core-ui`, plus the Compose BOM and Koin BOM (see an existing module's
`build.gradle.kts` for the exact block — copy its structure, don't hand-roll a new one).
Register it in `settings.gradle.kts` and add it to `:androidApp:app`'s dependencies.
All versions come from `libs.versions.toml` — never hardcode a version in a module's
`build.gradle.kts`.

After changing anything in `domain`, `data`, `core` or `shared`, dependent Android modules
need a Gradle sync/rebuild. A normal Android Studio run does this automatically. If you see
stale behavior right after a shared-module change, suspect this first.
