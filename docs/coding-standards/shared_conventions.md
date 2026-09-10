# Shared conventions

Rules in this document apply to both the Kotlin/Android codebase and the
Swift/iOS codebase. Platform-specific rules live in
`android_developer_guide.md` and `ios_developer_guide.md`.

These rules are **enforced by tooling** (Detekt for Kotlin, SwiftLint for
Swift, both run in CI — see `ci.yml`). A coding agent must not treat these
as optional style preferences: CI fails the build on violation, and there
is no override short of an explicit, human-approved suppression comment
with a stated reason.

## No deprecated APIs

Never call an API marked `@Deprecated` (Kotlin) or `@available(*, deprecated)`
(Swift). This is enforced automatically:
- Kotlin: `allWarningsAsErrors = true` turns every deprecation warning into
  a build failure (see each module's `compilerOptions`).
- Swift: SwiftLint has no built-in "no deprecated" rule; Xcode's own build
  treats deprecation as a warning, not an error, by default. Do not silence
  these warnings — if you hit one, replace the call with its non-deprecated
  replacement instead of suppressing it.

If a deprecation is unavoidable (e.g. a third-party library hasn't shipped
a replacement yet), suppress it narrowly (`@Suppress("DEPRECATION")` /
`@available(*, deprecated)`-wrapped call site) with a comment explaining
why, not at the file or module level.

## Naming

- Packages/modules: lowercase, no underscores (`featurehistory` is wrong;
  `feature-history` as a module name, `dev.roozbahani.trailmetrics.feature.history`
  as a package, is correct).
- Classes/types: `PascalCase`. Interfaces are not prefixed with `I`
  (`ActivityHistoryRepository`, not `IActivityHistoryRepository`).
- Functions/properties: `camelCase`.
- Test functions: descriptive sentence-like names
  (`` `saves activity with recalculated calories`() `` in Kotlin,
  `func test_savesActivity_recalculatesCalories()` in Swift), not `test1`.
- Booleans: read as a question (`isLoading`, `canStart`, `hasPermission`),
  never a bare noun.

## No dead code, no commented-out code

Don't leave commented-out blocks of code in a commit. If it's not needed,
delete it — git history is the backup, not a comment block.

## Module boundaries are load-bearing

Before adding an import that crosses a module boundary, check
`docs/architecture/OVERVIEW.md`'s module graph. In particular:
- Nothing in `domain` may import `android.*`, `androidx.*`, `UIKit`, or any
  Compose/SwiftUI type.
- Nothing in `core`'s `commonMain` may import a UI framework of any kind
  (Compose or SwiftUI) — see `core/README.md`.
- `shared` is the only module allowed to `export()` Kotlin code to iOS.

If a task seems to require violating one of these boundaries, stop and
flag it rather than working around it — it usually means the task needs a
different module, not an exception to the rule.

## Commit and branch discipline

- One feature or fix per branch, branched from `feature/kmp-migration-main`
  (or `main` once migration is complete).
- Commit messages: `type(scope): summary` — see recent git history for the
  established `type` vocabulary (`feat`, `fix`, `refactor`, `build`, `docs`,
  `test`).
- A coding agent never commits or merges on its own initiative. It prepares
  the diff; the human reviews, tests, commits, and merges. See
  `docs/workflow/coding_agent_workflow.md`.
