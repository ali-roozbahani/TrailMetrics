# ADR-003: `core` (KMP) and `core-ui` (Android-only) are separate modules

## Status
Accepted.

## Context
`core` originally held both platform-agnostic code (navigation route
models, UI error classification) and Android Compose UI code (design
system theme, `MetricCell`, Google Maps Compose components) across
`commonMain`/`androidMain` source sets in a single KMP module.

Converting `core` to KMP (to share `AppRoute` and `RouteUiError` with iOS)
while keeping the Compose code in its `androidMain` source set caused
`:core:compileKotlinIosArm64` and `:core:compileKotlinIosSimulatorArm64`
to fail with:

```
IncompatibleComposeRuntimeVersionException: The Compose Compiler requires
the Compose Runtime to be on the class path, but none could be found.
```

This happened despite `iosMain`/`commonMain` containing zero
`@Composable` code.

## Decision
Split the module in two:
- **`core`** (root, KMP): `commonMain` only. Holds `AppRoute` and
  `RouteUiError` — nothing else. No Compose plugin applied.
- **`core-ui`** (`androidApp/core-ui`, plain Android library, not KMP):
  holds the Compose design system and Google Maps Compose components that
  used to live in `core`'s `androidMain`.

## Reasoning
Once the Compose compiler Gradle plugin is applied to a module via
`plugins { alias(libs.plugins.kotlin.compose) }`, it instruments **every**
Kotlin compilation task in that module — not just the Android or JVM one —
because it registers as an IR generation extension for the whole module,
regardless of which source set actually contains `@Composable` code. Since
this project's iOS targets never add a Compose Runtime dependency (by
design — see ADR-001), any KMP module with the Compose plugin applied and
an iOS target will fail to compile, even with no Composable usage on that
target.

The only reliable fix is to keep Compose-dependent code out of any module
that also targets iOS. A plain Android-only module has no such constraint.

## Consequences
- `core` stays genuinely platform-agnostic and lightweight — it has no
  Android or iOS source sets, only `commonMain`.
- `core-ui` depends on `core` (for `RouteUiError`) and `domain` (for models
  used by map components), and lives under `androidApp/` alongside the
  other Android-only modules.
- Any future shared design tokens (raw color/spacing values, not Compose
  `Color`/`TextStyle` objects) can go in `core`'s `commonMain`; the moment
  a piece of design-system code needs `@Composable`, it belongs in
  `core-ui`, not `core`.
- This is a general rule for the whole module graph, not just `core`: no
  KMP module that targets iOS may apply the Compose compiler plugin,
  regardless of which source set the Compose code would live in.
