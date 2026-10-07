# Epic: Protected paths review 2: protect the control plane, open the product code

- **Slug:** protected-paths-review-2
- **Status:** proposed
- **Integration branch:** none. A chain of plain PRs against `main`, one at a time. Every
  subtask below touches a protected path (`.github/`, `.claude/`, `scripts/`, `docs/epics/` or
  a path this epic opens only in its last subtasks), so the human merges each one and none
  counts toward the trial of `docs/epics/agentic-dev-loop.md`, Decision 7.
- **Goal:** After the subtasks, `.github/CODEOWNERS` protects what controls or judges the agent
  (the control plane: workflows, the gate and its scripts, the reviewer, the process skills,
  agent settings and instruction files, lint config) and the build and supply-chain files that
  execute code or pull in dependencies, and no longer protects the product code: the Kotlin
  sources, tests and docs under `shared/`, the `SharedKit` sources, the persistence code under
  `data/.../local/{database,dao,entity}/` and the exported schemas under `data/schemas/`. Each
  product path opens only after the compensating controls this plan names for it are on
  `main`.
- **Out of scope:** any app behavior; `build.gradle.kts`, `settings.gradle.kts`,
  `gradle.properties`, `gradle/`, `gradlew*`, `Package.swift`, `Package.resolved` and the Xcode
  project (all stay protected, Decision 1); `docs/architecture/` and `docs/epics/` (stay
  protected: they record the human's decisions); `config/kover-floors.properties` (stays
  unprotected, guarded by its ratchet); GitHub repository settings and branch protection; the
  CI reviewer's model, prompt and permissions; the trial of `agentic-dev-loop`; the code
  under `data/.../local/mapper/` and `data/.../local/repository/`, which is not protected today
  and stays open.
- **Approved by:** <left for the human>

## Principle (as the human stated it)

The workflow and the infrastructure are protected and change only with the human's approval.
The business logic and the modules stay open for development speed: a feature or fix that
changes `domain`, `data` (schema and database included) or the Kotlin-to-Swift code in
`shared` is normal development, not a reason to escalate. Safety for product code comes from
tests, the local gate, the reviewer and the CI annotation, not from paths. A schema or
database change is made safe by tests.

Three things must stay true after this epic. Where each is enforced on `main` today:

1. **The agent cannot change the gate, the reviewer, the workflows or its own permissions
   without the human.**
   - `.github/CODEOWNERS` owns `/.github/`, `/.claude/` (except the four reference skill
     files), `/CLAUDE.md` and every gate script under `/scripts/` (its sections "Agent and
     repository configuration" and "The gate and its tooling"). Branch protection on `main`
     requires code owner review (the human's stated fact), so a PR touching them needs the
     human's approval.
   - The machine token has no `workflow` scope, so GitHub refuses the agent's push of a
     change under `.github/workflows/` (`docs/epics/agentic-dev-loop.md`, Decision 1).
   - The CI reviewer takes `.github/CODEOWNERS`, the protected-path classifier, `BOARD.md`,
     every `.claude/` directory and every `CLAUDE.md`/`CLAUDE.local.md` from the base branch,
     and deletes `.mcp.json` and symlinks from the tree it reads, so a PR cannot change the
     rules it is judged by (`.github/workflows/pr-review.yml`, step "Build review inputs");
     the rule-change list also comes from the base's script (step "Rule changes from the
     base").
   - The agent never merges a PR that touches a protected path (`tm-agent-loop`, section 8,
     condition 6; `tm-pr-workflow`, "Boundaries").
2. **The agent cannot lower or remove tests or floors without the reviewer escalating.**
   - `tm-pr-review` item 5 (a removed test file or function, loosened assertions, a skip, an
     excluded test task, a lowered or removed Kover floor) is `ESCALATE_TO_HUMAN` unless the
     task asks for it.
   - `scripts/check-kover-floors.sh --base` fails when a floor in
     `config/kover-floors.properties` is lower than on the base or an entry is gone while its
     module exists; it runs in the gate in every classification and in CI's `android` job
     ("Kover floors check"). `koverVerify` enforces the floors in the gate and in CI.
   - `tm-pr-review` item 10 (the rule-weakening signal) escalates a removed or rewritten rule
     line in a skill or `CLAUDE.md`.
3. **The agent cannot merge without both required checks, the local verdict and the CI
   annotation.**
   - `tm-agent-loop` section 8: both required CI checks green on the head SHA (condition 1),
     the CI annotation `APPROVE` (condition 4, read as in section 7), the local verdict
     `APPROVE` for that SHA (condition 5); "Allow auto-merge" stays off and `--auto` is
     forbidden.
   - Branch protection requires `Android — Lint, Detekt, Tests, Build`, `iOS — SwiftLint,
     Build` and `Review — pr-reviewer`, up to date with `main` (the human's stated facts).
   - The push hook `scripts/claude-hooks/block-git-push.sh` blocks a `git push` from a Claude
     Code session unless the gate's pass marker is newer than the last commit
     (`tm-pr-workflow`, "Tier 1").
   - Limits, stated honestly: condition 5 and the gate before a push are enforced by the skill
     and the Claude Code hook, not by GitHub (a push from a plain terminal skips the hook,
     `tm-pr-workflow`, "Where enforcement and history differ"). GitHub's hard line is the
     three required checks: CI re-runs the tests and the reviewer on every PR. Note also that
     the `Review — pr-reviewer` check is green for `ESCALATE_TO_HUMAN` too, so it is the
     annotation (condition 4), not the check's colour, that stops an agent merge.

Opening a product path changes none of these three. It changes one thing only: after the
`agentic-dev-loop` trial, a PR that touches only opened paths and meets all six conditions
can be merged by the agent instead of waiting for the human.

## Why

`.github/CODEOWNERS` protects, besides the control plane, three groups of product code: the
section "The Kotlin to Swift boundary" (`/shared/`, `/iosApp/Packages/SharedKit/`) and the
section "Persistence" (`/data/src/*Main/.../data/local/database/`, `.../local/dao/`,
`.../local/entity/`, `/data/schemas/`). The first epic (`docs/epics/protected-paths-review.md`,
"Out of scope" and Decision 1) kept them protected without giving a reason. The cost: every
feature that adds a `KoinHelper` getter for iOS (`tm-kmp-shared`, "Adding a dependency iOS
needs", step 2) or changes a stored field is a protected PR that escalates and waits for the
human, which is the normal path of feature work on both platforms.

The investigation (section "Findings") shows that none of these product files runs code at
build time on its own: the only executable files in those directories are
`shared/build.gradle.kts` and `iosApp/Packages/SharedKit/Package.swift`, and both have their
own CODEOWNERS lines (`build.gradle.kts`, `Package.swift`) that keep them protected after the
directory lines go. What the directory lines did protect is real, though: the Swift-visible
API and the user's stored data. The first is already guarded by the reviewer and the iOS
build; the second has no automated guard today (no migration, no migration test, no schema
check). So this plan adds the missing controls first and opens each path after them.

It also found control-plane files that are **not** protected today (Findings, F7): agent
instruction files below the root, and lint configuration files that the lint tools pick up
from subdirectories. Closing them is part of the human's first concern ("the agent must not be
able to bypass or change the workflow").

## Findings (from the files on `main` at `24aee7e`)

**F1. What is in `shared/`** (`git ls-files shared`):
- Build: `shared/build.gradle.kts` (plugins KMP, Android KMP library, SKIE, Kover; the
  `binaries.framework` block that `export()`s `domain`, `data`, `core`; dependencies). A Gradle
  script runs arbitrary code at configuration time: control plane. Today its last matching
  CODEOWNERS line is `/shared/`; without that line its last match is `build.gradle.kts`, so it
  stays protected (checked with `scripts/check-protected-paths.sh --files`, which reports the
  last matching pattern).
- Source, compiled only: `commonMain/.../di/KoinInit.kt`, `androidMain/.../di/PlatformModules.android.kt`,
  `iosMain/.../di/KoinHelper.kt`, `KoinInitIos.kt`, `PlatformModules.ios.kt`, and
  `iosMain/.../testsupport/SwiftTestSupport.kt` (test-only helpers that Swift fakes in
  `iosApp/Packages/*/Tests` use; `shared/README.md`, "What lives here").
- Tests: `iosTest/.../testsupport/SwiftTestSupportTest.kt`. No `commonTest` or Android host test
  (`shared/build.gradle.kts`, the Kover comment: 0% own line coverage, no floor on purpose).
- Docs and other: `shared/README.md`, `shared/.gitignore`. No script, no executable file.
- The Kotlin-to-Swift conversion is configured in `shared/build.gradle.kts` (SKIE applied
  there and only there, `shared/README.md`), and the API Swift sees is the public API of
  `domain`, `data` and `core` (exported), plus `KoinHelper`. `domain/`, `data/` outside the
  persistence paths, and `core/` are **not** protected today: most of the Swift-visible API is
  already open.

**F2. What is in `iosApp/Packages/SharedKit/`**: `Package.swift` (one `binaryTarget` pointing at
`shared/build/XCFrameworks/debug/TrailMetricsShared.xcframework` and one `target`), the source
`Sources/SharedKit/SharedKit.swift` (the single line `@_exported import TrailMetricsShared`) and
`.gitignore`. A Swift package can only run build-time code (a plugin, a macro) when its
`Package.swift` declares it; `Package.swift` is control plane and keeps its own line
`Package.swift`. The source is compiled only.

**F3. What is in the persistence paths**: `local/database/` holds `TrailMetricsDatabase.kt`
(`@Database(entities = [ActivityEntity::class], version = 1, exportSchema = true)`),
`Converters.kt` (stored form of `ActivityType` and coordinate lists), `DatabaseBuilder.kt`
(`getRoomDatabase`: bundled SQLite driver, no migrations added) and the `android`/`ios` actuals
of `getDatabaseBuilder()` (the database file name and directory). `local/dao/ActivityDao.kt`
(four queries), `local/entity/ActivityEntity.kt` (table `tbl_activities`), and
`data/schemas/dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase/1.json`
(Room's exported schema, written by Room's KSP processor to the directory that
`data/build.gradle.kts` sets in its `room3 { schemaDirectory(...) }` block). All compiled or
data only; the KSP processor itself and its configuration are in `data/build.gradle.kts`
(protected by `build.gradle.kts`).

**F4. What protects stored data today.**
- Present: `ActivityHistoryRepositoryImplTest` (commonTest, abstract) runs on the Android host
  with an in-memory database through Robolectric and the platform driver, and on the iOS
  simulator with the app's bundled driver (`ActivityHistoryRepositoryImplAndroidHostTest`,
  `ActivityHistoryRepositoryImplIosTest`); it covers the DAO through the repository.
  `ConvertersTest` pins the stored names of every `ActivityType` and says they "must change
  only together with a database migration". Reviewer item 5 escalates a loosened assertion.
- Missing: there is no migration and no migration test (`git grep -i migration` finds only the
  `ConvertersTest` comment and unrelated text); the catalog has no Room testing artifact
  (`gradle/libs.versions.toml` lists only `room3-runtime` and `room3-compiler`); no script or
  CI step looks at `data/schemas/`; nothing checks that the build leaves the exported schema
  unchanged; nothing pins the database file name. Every database test opens a **fresh
  in-memory** database, so none of them would see that an entity change without a version bump
  and migration breaks opening an existing user's database. The Kover filters in
  `data/build.gradle.kts` name generated classes in `local/dao` and `local/database`; a
  renamed class there changes coverage numbers, which the floor check catches only as a drop.

**F5. What catches a broken Swift side today.** The gate runs SwiftLint, the hash-gated
XCFramework build (`scripts/build-kmp-framework.sh`, whose `SOURCE_DIRS` include
`shared/src`), the `xcodebuild` app build and the iOS package tests (`History`, `Route`,
`Tracking` have `Tests/`) whenever the diff touches `shared/` (the gate's iOS scope filter,
checked by `scripts/check-ios-scope.sh --self-test`). CI's `ios` job runs the same build and
package tests on every non-light PR, without a path filter. So an API change that breaks Swift
compilation or a tested Swift behavior is caught. Gaps:
- CI's "Run iOS simulator tests" step runs `:domain:iosSimulatorArm64Test` and
  `:data:iosSimulatorArm64Test` only; `shared`'s `iosTest` (`SwiftTestSupportTest`) runs only
  in the local gate's `allTests` (CI's `android` job runs on Ubuntu, where iOS tests do not
  run). A PR pushed without the hook would not run it anywhere.
- No check compares the exported Swift API with the base (no API dump). An exported change
  that compiles and that no Swift test exercises is seen only by the reviewer (item 6).
- `koin-test` is in the catalog but no module uses it: no test verifies the Koin graph that
  `initKoin` and the platform modules build, so a missing binding fails only at app start. The
  same is true for `data/.../di/*.kt`, which is already open.
- Reviewer item 5 names tests, assertions and floors, not test support in a main source set
  (`shared/.../testsupport/SwiftTestSupport.kt`) or the Swift fakes package
  `iosApp/Packages/TestSupport` (unprotected today). Weakening a fake can make Swift tests pass
  without asserting anything.

**F6. Who reads or describes the protected list.** `.github/CODEOWNERS` (its header comments
and section comments); `scripts/check-protected-paths.py` (`UNOWNED_PATTERNS`, the module
docstring, the self-test's fixtures, which are synthetic and do not read the real file);
`.github/workflows/pr-review.yml` and the gate (they run the classifier, they do not list
paths); `tm-agent-loop` (condition 6), `tm-pr-review` (item 3), `tm-pr-workflow`
("Boundaries"), `epic-orchestration` ("allowed_paths conventions") all defer to CODEOWNERS and
name no product path; `CLAUDE.md`, `docs/architecture/` and the module READMEs name none
either. `docs/epics/protected-paths-review.md` (Decision 1 and "Out of scope") lists `shared/`
and the persistence paths as staying protected. `scripts/classify-changes.sh` does not use the
protected list (its own non-source allowlist decides `light`/`full`); its fixtures mention
`shared/` paths only as source files, which stays true. `scripts/check-ios-scope-fixtures/`
mentions `shared/build.gradle.kts` only as an iOS-scope input. There is no
`scripts/check-protected-paths-fixtures/` directory (the first epic's S4 listed it in
`allowed_paths`; the self-test is inline in the `.py` file).

**F7. Control-plane files that are not protected today** (`check-protected-paths.sh --files`
reports each as `unprotected`):
- Agent instructions and configuration below the root or beside it: a `CLAUDE.md` in a
  subdirectory (the pattern is `/CLAUDE.md`, anchored), `CLAUDE.local.md`, `.mcp.json`, a
  `.claude/` directory in a subdirectory (the pattern is `/.claude/`). `pr-review.yml` already
  treats all of these as agent instructions (it replaces them with the base's copies or
  deletes them), and `check-skill-rule-changes` covers a nested `CLAUDE.md`'s removed rule lines
  (its fixture `claude-md-nested`), but an added nested file is neither protected nor
  escalated, and a local session would read it.
- Lint configuration picked up from subdirectories: a module-level `lint.xml` (Android lint)
  and a nested `.swiftlint.yml` (SwiftLint). Only `/iosApp/.swiftlint.yml` and `/config/detekt/`
  are protected; the root `build.gradle.kts` points detekt at `config/detekt/detekt.yml` and has
  no lint configuration. That Android lint and SwiftLint read these files is their documented
  behavior, not verified in this repo (S2 verifies it).
- Build scripts under other names: Gradle also runs Groovy build scripts (`*.gradle`) and builds
  a `buildSrc/` directory on its own; only `build.gradle.kts` and `settings.gradle.kts` are
  protected by name. Not verified in this repo (S2 verifies it).
- `--validate` reports a pattern that matches no tracked file as a problem
  (`run_validate`), so protecting a path that does not exist yet (`.mcp.json`, `lint.xml`,
  `buildSrc/`) needs a change to the validator, not only to CODEOWNERS.

**F8. Drift in the process skills** (fixed by S7a, which edits the same text): `tm-pr-workflow`,
"Where enforcement and history differ", says "The required approval count is **0**: review
before merge is enforced by the human, not by GitHub" and "The review check is not required
yet ... until S5 of `docs/epics/agentic-dev-loop.md`"; the human states that code owner review
and the `Review — pr-reviewer` check are required on `main`.

## Decisions

1. **Stays protected (control plane and build).** Everything protected today except the
   groups in Decisions 2 to 4: `.github/`; `.claude/` except the four reference skill files;
   `CLAUDE.md`; the gate's scripts under `scripts/`; `docs/architecture/`, `docs/epics/`;
   `settings.gradle.kts`, every `build.gradle.kts` (including `shared/build.gradle.kts`),
   `gradle.properties`, `gradle/`, `gradlew`, `gradlew.bat`; every `Package.swift` and
   `Package.resolved` (including `iosApp/Packages/SharedKit/Package.swift`); the Xcode project;
   `config/detekt/`, `iosApp/.swiftlint.yml`. Reason: each runs code at build or gate time,
   pulls in dependencies, configures a check, or is an instruction the agent follows.
   *Rejected:* opening `shared/build.gradle.kts` with the rest of `shared/` (it is a Gradle
   script and holds the XCFramework export and SKIE configuration; a dependency change there
   is `tm-pr-review` item 7, but arbitrary build-time code is not something the reviewer can
   bound).
2. **`shared/` opens, except its build file** (S7a). The directory line `/shared/` is removed;
   `shared/build.gradle.kts` stays protected through `build.gradle.kts`. Opened: `src/**`
   (Koin composition, `KoinHelper`, the Swift test support), `iosTest`, `README.md`,
   `.gitignore`. The risk is a change to what Swift sees; it is carried by reviewer item 6
   (`@Throws`/SKIE and any change to Swift-visible `Flow`/`suspend` signatures or `KoinHelper`
   that the policy does not sanction or the task does not name: escalate), the iOS build and
   package tests in the gate and in CI (F5), and two controls added first: CI runs `shared`'s
   `iosTest` (S3), and reviewer item 5 covers test support (S6). *Rejected:* keeping
   `KoinHelper.kt` protected on its own: it is the step every iOS feature needs, the same
   Swift-visible API is already open in `domain`/`data`/`core`, and item 6 escalates exactly the
   unsanctioned changes. *Rejected:* waiting for a Swift API dump check: it needs a tool that
   is not in the repo (open question Q5).
3. **`iosApp/Packages/SharedKit/` opens, except `Package.swift`** (S7a). The directory line is
   removed; `Package.swift` stays protected through `Package.swift`. Opened: `Sources/**` and
   `.gitignore`. Swift source here is compiled and linted like every other package; the
   package's build-time behaviour lives in `Package.swift` only. *Rejected:* keeping it
   protected: its one source line has no control-plane role.
4. **Persistence opens after its controls exist** (S7b). The four persistence lines are removed
   once S4, S5 and S6 are merged. The risk is user data: a change that makes an existing
   database fail to open (Room's identity check) or silently lose rows. The controls:
   - **Schema check** (S4): a script `scripts/check-room-schema.sh` (`.py`, fixtures,
     `--self-test`), run in the gate in every classification and in CI's `android` job, that
     compares the head with the base and fails when (a) an exported schema file that exists on
     the base is deleted, or its `database.version` or `identityHash` changes; (b) the
     `@Database` `version` goes down; (c) the version goes up from M to N and the diff does not
     add `N.json` with `database.version` N, does not define `MIGRATION_M_N` under
     `data/src/commonMain/.../local/database/`, or does not touch a test under
     `data/src/commonTest/.../local/database/` that contains the text `MIGRATION_M_N`; (d) the
     head's current version has no schema file; (e) a file under `data/src/*Main/` calls a
     `fallbackToDestructiveMigration` variant. Exact text and path checks only; whether the
     test really proves the data survives is the reviewer's (S6).
   - **Schema export freshness** (S4): after the build, the gate and CI's `android` job fail
     when `data/schemas/` has a modified or untracked file. This is what catches an entity or
     converter change at an unchanged version: Room rewrites the current version's schema
     file, the check sees it, and rule (a) forbids committing the rewrite.
   - **Migration harness** (S5): an abstract `commonTest` suite with an Android host and an
     iOS subclass (the shape of `ActivityHistoryRepositoryImplTest`) that writes a database at
     an old version with plain SQL from that version's exported schema, inserts rows, opens it
     with the app's builder and migration list, and asserts every row reads back. At version 1
     it proves the current Room setup opens a version 1 database written outside Room and keeps
     its rows. `getRoomDatabase` gets the app's migration list (empty at version 1), so the
     test and the app use the same list. A pinned test of the database file name (the
     `ConvertersTest` pattern), so a rename is a changed assertion (item 5). No new dependency.
   - **Reviewer rule** (S6): a new `tm-pr-review` item for persistence: a diff that changes an
     entity, the `@Database` annotation, a converter's stored form, `data/schemas/` or the
     database builder needs the version bump, the new schema file, `MIGRATION_M_N` and a
     harness case that inserts rows at M and asserts them at N; missing any is blocking. A
     migration that drops a table or column, or deletes or rewrites rows, and any change to the
     database file name, directory or driver, is `ESCALATE_TO_HUMAN` with the reason
     `critical` (open question Q3).
   `data/schemas/` opens together with the code: with rule (a) its existing files are
   append-only, and a new file must match the version bump.
   *Rejected:* opening persistence now and relying on the reviewer alone: no test today opens
   an existing database (F4), so the reviewer would have nothing to check against.
   *Rejected:* Room's `MigrationTestHelper`: it is in a Room testing artifact that is not in
   the catalog, so it needs a new dependency (open question Q2).
   *Rejected:* keeping `data/schemas/` protected while the code opens: every entity change
   adds a schema file, so every schema change would still escalate, against the principle.
5. **Close the control-plane gaps of F7** (S2). Protect, at any depth: `CLAUDE.md`,
   `CLAUDE.local.md`, `.mcp.json`, `.claude/` (the four reference skill files stay ownerless,
   after it), `lint.xml`, `.swiftlint.yml`, `*.gradle`; and `/buildSrc/`. `--validate` learns a
   short list of patterns that may match no tracked file yet (they protect a file before it
   exists), the same way `UNOWNED_PATTERNS` lists the only ownerless lines.
   *Rejected:* adding a reviewer rule instead: an unprotected PR can be agent-merged after the
   trial, and an instruction or lint file changes what judges every later PR.
6. **Self-test against the real CODEOWNERS.** Today's self-test uses synthetic CODEOWNERS
   texts only (F6). S2 adds a table of real paths with their expected status, checked against
   the committed `.github/CODEOWNERS` in `--self-test`: every control-plane path of Decision 1
   and 5 `protected` (with the pattern that wins), every opened product path `unprotected`.
   S7a and S7b move rows from `protected` to `unprotected` in the same PR that edits
   CODEOWNERS, so the gate and CI fail if CODEOWNERS and the table disagree.
7. **Order.** Controls first, each its own PR; then one CODEOWNERS PR per group (S7a for
   `shared/` and `SharedKit`, S7b for persistence), so `shared/` does not wait for the
   persistence work. Every subtask is protected (each touches `.github/`, `.claude/`,
   `scripts/` or a path that is still protected when it runs), so the human merges all of them.
8. **Changes to `.github/workflows/`** (S3, S4) are pushed by the human
   (`agentic-dev-loop`, Decision 1): the agent builds and runs the gate locally, stops before
   the push, and hands over.
9. **The first epic's text.** `docs/epics/protected-paths-review.md`, Decision 1, gets one
   sentence pointing here (as that epic's Decision 9 did for `agentic-dev-loop`); nothing else
   in it changes.

## Path groups

| Path group | Files on `main` | Today | Proposed | Reason (evidence) | Must exist first (state today) | Subtask |
|---|---|---|---|---|---|---|
| shared build file | `shared/build.gradle.kts` | protected (`/shared/`) | protected (`build.gradle.kts`) | Gradle script, runs at configuration; SKIE and XCFramework export (F1) | none | S7a keeps it, S2 table proves it |
| shared source | `shared/src/{commonMain,androidMain,iosMain}/**` | protected | open | compiled only; Swift-visible API mostly already open in `domain`/`data`/`core` (F1) | item 6 (exists); iOS build and package tests in gate and CI (exist); CI runs `shared` `iosTest` (missing, S3); item 5 covers test support (missing, S6) | S7a |
| shared tests | `shared/src/iosTest/**` | protected | open | test code, run by `allTests` (F1) | item 5 (exists); CI run (missing, S3) | S7a |
| shared docs, other | `shared/README.md`, `shared/.gitignore` | protected | open | not executed (F1) | item 9, docs follow code (exists) | S7a |
| SharedKit `Package.swift` | `iosApp/Packages/SharedKit/Package.swift` | protected (`/iosApp/Packages/SharedKit/`) | protected (`Package.swift`) | declares targets, plugins, binary path (F2) | none | S7a keeps it, S2 table proves it |
| SharedKit sources | `iosApp/Packages/SharedKit/Sources/**`, `.gitignore` | protected | open | one re-export line, compiled only (F2) | SwiftLint, iOS build, package tests in gate and CI (exist) | S7a |
| persistence code | `data/src/*Main/.../local/database/**`, `data/src/commonMain/.../local/{dao,entity}/**` | protected | open | compiled only; risk is stored data (F3, F4) | repository suite (exists); `ConvertersTest` pins (exists); migration harness and file-name pin (missing, S5); schema check (missing, S4); reviewer rule (missing, S6) | S7b |
| persistence schemas | `data/schemas/**` | protected | open | data written by Room's KSP step (F3) | schema check and export freshness (missing, S4) | S7b |
| agent instructions below the root | nested `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, nested `.claude/` | unprotected | protected | read by agent sessions; CI reviewer already distrusts them (F7) | `--validate` accepts not-yet-existing patterns (missing, S2) | S2 |
| nested lint config | `lint.xml`, `.swiftlint.yml` at any depth | unprotected (except `/iosApp/.swiftlint.yml`) | protected | lint tools read them from subdirectories (F7, verified in S2) | same | S2 |
| other Gradle build scripts | `*.gradle`, `/buildSrc/` | unprotected | protected | Gradle runs them (F7, verified in S2) | same | S2 |

## Subtasks

```yaml
- id: S1
  title: Plan and board record
  branch: chore/protected-paths-review-2-plan
  skills: [tm-pr-workflow, epic-orchestration]
  depends_on: []
  allowed_paths:
    - docs/epics/protected-paths-review-2.md
    - BOARD.md
  acceptance:
    - This plan is committed, status proposed; after the human's review it is committed as the human saved it, with the "Approved by" line filled in.
    - BOARD.md has one epic record with this slug and a unique Order; check-board.sh passes.
  tier2: none (docs only, nothing user-visible changes)

- id: S2
  title: Protect agent instruction files, nested lint config and other build scripts; self-test against the real CODEOWNERS
  branch: chore/protect-control-plane-gaps
  skills: [tm-pr-workflow, tm-pr-review]
  depends_on: [S1]
  allowed_paths:
    - .github/CODEOWNERS
    - scripts/check-protected-paths.py
    - scripts/check-protected-paths.sh
    - .claude/skills/tm-pr-review/SKILL.md    # item 3, only where its text would be wrong
    - docs/epics/protected-paths-review.md    # Decision 9: one pointer sentence
    - BOARD.md
  acceptance:
    - CODEOWNERS owns CLAUDE.md, CLAUDE.local.md, .mcp.json, .claude/, lint.xml, .swiftlint.yml and *.gradle at any depth and /buildSrc/; the four reference skill lines stay ownerless and after .claude/; `--validate` passes.
    - `--validate` accepts a pattern that matches no tracked file only when it is in a named list in the script, and still rejects any other such pattern (both shown, and self-test cases for both).
    - "`--self-test` has a table of real paths classified against the committed .github/CODEOWNERS: at least one path per Decision 1 group and per new pattern is protected with the expected winning pattern (including shared/build.gradle.kts by /shared/ today, iosApp/Packages/SharedKit/Package.swift, data/CLAUDE.md, androidApp/app/lint.xml, iosApp/Packages/History/.swiftlint.yml, settings.gradle, buildSrc/x.kt, .mcp.json), and the four reference skill files and an unprotected source file are unprotected; the table was shown failing when a CODEOWNERS line was removed."
    - "Shown in this repo, in a throwaway local branch never pushed: Android lint reads a module lint.xml and SwiftLint a nested .swiftlint.yml, and Gradle runs a Groovy build script or a buildSrc directory as F7 says; any that does not hold is reported, and its pattern is kept or dropped as the human decides."
  tier2: none (CI and scripts only, nothing user-visible changes)

- id: S3
  title: Run shared's iOS tests in CI
  branch: chore/ci-shared-ios-tests
  skills: [tm-pr-workflow, tm-testing]
  depends_on: [S1]
  allowed_paths:
    - .github/workflows/ci.yml
    - .claude/skills/tm-pr-workflow/SKILL.md   # only where it lists the tests CI's ios job runs
    - BOARD.md
  acceptance:
    - CI's ios job "Run iOS simulator tests" also runs :shared:iosSimulatorArm64Test; the CI log of the PR shows SwiftTestSupportTest ran.
    - Phase split: the agent stops before the push (ci.yml); the human pushes.
  tier2: none (CI only)

- id: S4
  title: Room schema check and schema export freshness in the gate and CI
  branch: chore/room-schema-check
  skills: [tm-pr-workflow, tm-kmp-shared, tm-testing]
  depends_on: [S1]
  allowed_paths:
    - scripts/check-room-schema.sh
    - scripts/check-room-schema.py
    - scripts/check-room-schema-fixtures/
    - scripts/pre-push-check.sh
    - .github/workflows/ci.yml
    - .github/CODEOWNERS                      # owned entries for the new script, fixtures
    - scripts/check-protected-paths.py        # real-path table rows for the new script (after S2)
    - .claude/skills/tm-pr-workflow/SKILL.md  # Tier 1 list of gate and CI steps
    - BOARD.md
  acceptance:
    - check-room-schema.sh --base fails (shown, one fixture each) for rules (a) to (e) of Decision 4 and passes on main's state, on an unchanged schema, and on a correct M to N bump with N.json, MIGRATION_M_N and a test naming it; its self-test was shown failing against a deliberately broken version.
    - The gate runs it in every classification and its self-test with the other self-tests; CI's android job runs both (base = the PR's base commit, as "Kover floors check" does).
    - The gate and CI's android job fail, after the build, when data/schemas/ has a modified or untracked file; shown green on main and red in a throwaway local branch that adds a field to ActivityEntity without a version bump.
    - Phase split: the agent stops before the push (ci.yml); the human pushes.
  tier2: none (scripts and CI only)

- id: S5
  title: Migration test harness and pinned database file name
  branch: chore/room-migration-harness
  skills: [tm-kmp-shared, tm-testing, tm-pr-workflow]
  depends_on: [S1]
  allowed_paths:
    - data/src/commonMain/kotlin/dev/roozbahani/trailmetrics/data/local/database/**
    - data/src/androidMain/kotlin/dev/roozbahani/trailmetrics/data/local/database/**
    - data/src/iosMain/kotlin/dev/roozbahani/trailmetrics/data/local/database/**
    - data/src/commonTest/kotlin/dev/roozbahani/trailmetrics/data/local/database/**
    - data/src/androidHostTest/kotlin/dev/roozbahani/trailmetrics/data/local/database/**
    - data/src/iosTest/kotlin/dev/roozbahani/trailmetrics/data/local/database/**
    - config/kover-floors.properties          # ratchet, if data's coverage rises
    - .claude/skills/tm-testing/SKILL.md      # how to write a migration case
    - .claude/skills/tm-kmp-shared/SKILL.md   # schema change procedure
    - BOARD.md
  acceptance:
    - getRoomDatabase adds the app's migration list (empty at version 1); the app opens its database exactly as before.
    - The harness writes a version 1 database with plain SQL from 1.json's createSql into a file, inserts rows, opens it through the app's builder path and migration list, and asserts every field of every row; it runs on testAndroidHostTest and iosSimulatorArm64Test.
    - Shown red in a throwaway local branch for an entity field added without a version bump and migration, then green on the branch.
    - The database file name is one constant, used by both actuals, and a test pins its value.
    - No new dependency (catalog and build files untouched). If the harness cannot be built with the current dependencies, the agent stops and reports (open question Q2).
  tier2: none (tests and an unchanged database open path; nothing user-visible changes; the harness and DatabaseBuilder tests are the automated proof)

- id: S6
  title: Reviewer rules for persistence and test support
  branch: chore/review-persistence-and-test-support
  skills: [tm-pr-workflow, tm-pr-review]
  depends_on: [S4, S5]
  allowed_paths:
    - .claude/skills/tm-pr-review/SKILL.md
    - .claude/agents/pr-reviewer.md           # only if it states the item count
    - BOARD.md
  acceptance:
    - tm-pr-review has a persistence item as Decision 4 states it (blocking when the bump, schema file, MIGRATION_M_N or harness case is missing; ESCALATE_TO_HUMAN, reason critical, for a destructive migration or a change to the database file name, directory or driver), naming check-room-schema.sh and the harness by path.
    - Item 5 also covers test support used by tests in a main source set (shared/src/iosMain/**/testsupport/**) and the Swift fakes package (iosApp/Packages/TestSupport/**).
    - The description's item count and every other mention of the count match.
    - The rule-change list for the PR is shown (additions only expected; any listed line is explained).
  tier2: none (skill only)

- id: S7a
  title: Open shared/ and SharedKit sources
  branch: chore/open-shared-sources
  skills: [tm-pr-workflow, tm-pr-review]
  depends_on: [S2, S3, S6]
  allowed_paths:
    - .github/CODEOWNERS
    - scripts/check-protected-paths.py        # real-path table rows
    - .claude/skills/tm-pr-workflow/SKILL.md  # F8 drift in "Where enforcement and history differ"
    - BOARD.md
  acceptance:
    - CODEOWNERS no longer has /shared/ and /iosApp/Packages/SharedKit/; the section comment "The Kotlin to Swift boundary" is gone or says what stays (the build file and Package.swift by their own lines).
    - The real-path table moves shared/src/**, shared/README.md and SharedKit/Sources/** to unprotected; shared/build.gradle.kts stays protected with the winning pattern build.gradle.kts, SharedKit/Package.swift with Package.swift; --validate and --self-test pass, and the self-test was shown failing with the old table.
    - check-protected-paths.sh --files shows each opened path unprotected and the two build files protected.
    - tm-pr-workflow's lines on review enforcement and the review check match the human's stated branch protection (F8).
  tier2: none (CODEOWNERS and docs only)

- id: S7b
  title: Open the persistence paths
  branch: chore/open-persistence
  skills: [tm-pr-workflow, tm-pr-review]
  depends_on: [S4, S5, S6, S7a]
  allowed_paths:
    - .github/CODEOWNERS
    - scripts/check-protected-paths.py        # real-path table rows
    - BOARD.md                                # deletes this epic's record
  acceptance:
    - CODEOWNERS no longer has the four persistence lines or their section comment.
    - The real-path table moves the database, dao, entity and schemas paths to unprotected; --validate and --self-test pass, the self-test shown failing with the old table.
    - check-room-schema.sh, the export freshness step and the harness are on main and green on main (named with the PRs that added them).
    - The epic record is removed from BOARD.md in the last commit.
  tier2: none (CODEOWNERS only)
```

## Waves

One PR at a time (no integration branch; most subtasks share `BOARD.md`, and S2, S4, S7a,
S7b share `.github/CODEOWNERS` and `scripts/check-protected-paths.py`).

- Wave 1: S1
- Wave 2: S2, S3, S4, S5 in any order (all depend only on S1). Suggested: S2 first (it adds the
  real-path table that S4, S7a and S7b extend), then S3, S4, S5.
- Wave 3: S6 (needs S4 and S5 to name their files)
- Wave 4: S7a, then S7b

## Risks and what could go wrong

| Risk | Caught by | Gap and follow-up |
|---|---|---|
| A `shared/` change compiles but changes the exported Swift API in a way no Swift test sees | reviewer item 6 (escalates unsanctioned Swift-visible changes) | No API dump check. Not covered automatically; Q5. |
| A `KoinHelper` or platform module change leaves a binding missing; the app crashes at start | nothing automated (same today for the open `data/.../di/`) | Not covered; Q4 (Koin graph test with the catalog's `koin-test`). |
| An agent weakens `SwiftTestSupport` or a Swift fake so Swift tests pass vacuously | item 5 once S6 extends it | Before S6: not covered, so S7a waits for S6. |
| `shared`'s `iosTest` is skipped because the push came without the hook | CI after S3 | Before S3: only the local gate runs it, so S7a waits for S3. |
| An entity changes without a version bump; existing users' databases fail to open | export freshness (S4) sees the rewritten schema file; rule (a) forbids committing it; the harness (S5) fails to open the version 1 database | Covered after S4 and S5. |
| A version bump without a migration, or a migration without a test | S4 rule (c) | A test that names the migration but asserts nothing: reviewer (S6). |
| A migration that compiles and is tested but drops data on purpose (column removed) | S6 escalates it (`critical`) | Decision is the human's (Q3). |
| The database file name or directory changes; users silently get an empty database | pinned name test (S5) is a changed assertion, item 5 escalates; S6 escalates | Covered after S5 and S6. |
| A migration works on the platform SQLite (Android host) but not on the bundled driver | the harness also runs on the iOS simulator with the bundled driver (S5) | The Android app's bundled driver itself is not tested on the host (LEARNINGS, "BundledSQLiteDriver's Android artifact has no host-JVM native lib"); not covered on Android. |
| A Room upgrade (human PR) reformats schema files | rule (a) compares `version` and `identityHash`, not bytes | A real identity change on an upgrade fails the check; the human's PR then also changes the script (protected). |
| An agent adds a nested `CLAUDE.md`, `.mcp.json` or lint config | protected after S2 | Before S2: not covered; S2 comes first in wave 2. |
| A CODEOWNERS edit opens more than intended | the real-path table (S2) in the gate and CI; the CI reviewer classifies with the base's CODEOWNERS | Covered after S2. |
| A path pattern meant to protect a future file never matches because the tool reads another name | S2 verifies each tool's file name in this repo | Unverified ones are reported, not assumed. |
| Opening paths lets the agent merge persistence or `shared/` PRs after the trial | intended; the six merge conditions still hold | none |

## Open questions for the human

- **Q1. Include S2 (closing the control-plane gaps of F7) in this epic?** Options: (a) yes,
  before any path opens; (b) a separate epic later; (c) drop it. Recommendation: (a), because
  an unprotected nested instruction or lint file can change what judges every later PR,
  which is the human's first concern.
- **Q2. If the migration harness cannot be built with the current dependencies (S5), may S5 add
  Room's testing artifact (`MigrationTestHelper`)?** Options: (a) no, stop and report; (b) yes,
  named in S5's scope now. Recommendation: (a) first; decide (b) with the report in hand. I
  could not verify from the repository that the plain-SQL approach works with Room 3.0.2.
- **Q3. Destructive migrations and database location changes: escalate (`critical`) or only
  block without a test?** Options: (a) escalate; (b) treat as normal development with a test.
  Recommendation: (a): dropping user data is a product decision, not a code question.
- **Q4. Koin graph verification (`koin-test`, in the catalog, unused) as a prerequisite for S7a?**
  Options: (a) prerequisite; (b) follow-up board record. Recommendation: (b): the same gap
  exists today in the open `data/.../di/`, so it is not specific to `shared/`; adding it
  touches `shared/build.gradle.kts` (protected) and names a dependency.
- **Q5. Exported Swift API dump check.** Options: (a) follow-up task to find a tool; (b) accept
  reviewer item 6 as the control. Recommendation: (b) for now; there is no such tool in the
  repo and adding one is a new dependency.
- **Q6. `.gitignore` files.** They are unprotected today. `tm-pr-workflow` and
  `epic-orchestration` rely on the Android SDK properties file and the iOS secrets config being
  git-ignored. An edit that stops ignoring them is seen by the reviewer only. Options: (a)
  protect the root `/.gitignore`; (b) leave open. Recommendation: (a), as part of S2; I did not
  read the file's entries (the session's deny rules cover commands that name those files).
- **Q7. Board Order and `After`.** The record gets Order 45 and no `After`: it does not need
  `agentic-dev-loop` (Order 40, whose open parts are the test seam, UI test targets and the
  trial) to be gone first. Options: (a) as is; (b) `After: agentic-dev-loop`. Recommendation:
  (a).

## Epic-level Tier 2

Nothing user-visible changes in this epic (CODEOWNERS, scripts, CI, skills, tests of the
database open path). The automated proof on `main` after S7b:

- `scripts/check-protected-paths.sh --validate` (OK) and `--self-test` (all cases, including
  the real-path table) in the gate and CI's `android` job; the table's rows are the decided
  status of every path group above.
- `scripts/check-room-schema.sh --self-test` and the check against `main`, and the migration
  harness on `testAndroidHostTest` and `iosSimulatorArm64Test`.
- The first agent PR after S7a that touches only `shared/src/` shows on GitHub that no code
  owner review is requested (`gh api repos/{owner}/{repo}/pulls/<N>/requested_reviewers` and
  `mergeStateStatus`, as `tm-agent-loop` section 7 reads them); the agent reports it in that
  PR. This is the one behavior the scripts cannot show (GitHub evaluates CODEOWNERS itself),
  and the API shows it, so no human smoke check is needed.
