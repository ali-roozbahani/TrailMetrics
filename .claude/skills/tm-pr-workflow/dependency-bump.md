# Dependency version bump

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the section "Dependency version bump". The rules are unchanged; they are still cited as `tm-pr-workflow`, "Dependency version bump".

## Dependency version bump

A bump that deprecates APIs ends with no deprecated call and no suppression. With `allWarningsAsErrors = true`
(`tm-android`, "No deprecated APIs (Kotlin)") the compiler's deprecation warnings are the work list.

1. Bump the version (`gradle/libs.versions.toml`) in the first commit, then build every platform target: the
   Android build and `allTests`, and the iOS framework (`scripts/build-kmp-framework.sh`).
2. Take each deprecation warning as a work item and replace the call with the replacement that the library
   names (its `ReplaceWith`, release notes or migration guide). Decide by the receiver's declared type, never by a
   find and replace of a method name: the same name exists on unrelated types.
3. One commit per call-site family (the same old call replaced the same way).
4. Never silence a deprecation with `@Suppress("DEPRECATION")` or by lowering `allWarningsAsErrors`. A call with no
   replacement is a stop-and-report.
5. Run the gate, and the full UI scope when UI code changed (`scripts/classify-changes.sh --ui-scope` says which). The
   PR lists the bumped versions and each call-site family.
6. Kotlin, SKIE, the Compose compiler plugin, KSP and Room's KSP processor move together: a Kotlin bump checks
   that each supports the new Kotlin version.
