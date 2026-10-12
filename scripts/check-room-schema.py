#!/usr/bin/env python3
"""Room schema check and schema export freshness (docs/epics/protected-paths-review-2.md, Decision 4).

Run through scripts/check-room-schema.sh (the entry point). Standard library only, so it runs on
the stock python3 of macOS and ubuntu-latest without installing anything.

  check-room-schema.sh [--repo <dir>] --base <ref> [--head <ref>]
  check-room-schema.sh [--repo <dir>] --check-export-fresh
  check-room-schema.sh --self-test

--base compares two committed trees, <ref> and HEAD (or --head), never the working tree. Exact
text and path checks only. It fails (exit 1, one message per problem on stderr, each naming its
rule) when:

  (a) a schema file under data/schemas/ that exists on the base is deleted, or its
      `database.version` or `database.identityHash` changes (other bytes may change: a Room
      upgrade can reformat the file);
  (b) the `version` of the @Database annotation goes down;
  (c) the version goes up from M to N and, for every step k -> k+1 from M to N (one step for a
      bump of one), the diff does not add `<k+1>.json` with `database.version` k+1, the head does
      not define `MIGRATION_k_<k+1>` (`val` or `object`) in a file under
      data/src/commonMain/.../local/database/, or no test under
      data/src/commonTest/.../local/database/ that the diff adds or changes contains the text
      `MIGRATION_k_<k+1>`;
  (d) the head's @Database version has no `<version>.json` (with that `database.version`);
  (e) a file under data/src/<any>Main/ contains `fallbackToDestructiveMigration` (every variant:
      the plain call, OnDowngrade, From; tests are not looked at).

It fails closed (exit 1) when it cannot apply the rules: no or more than one @Database annotation
under data/src/*Main/, a version that is not an integer literal, more than one schema directory
under data/schemas/ (it supports exactly one database), a file there that is not
`<dir>/<version>.json`, a schema file that is not JSON or has no integer `database.version` or no
`database.identityHash`. Exit 2 for a usage or git error (no base, a base that is not a commit, not
a git repository), never a pass.

--check-export-fresh runs after the build: it fails (exit 1) when `git status` lists a modified,
deleted or untracked file under data/schemas/. Room's KSP step rewrites the current version's file
when an entity changes, and writes a new file for a new version; either way the change needs a
version bump and a migration, or must be reverted. A converter that keeps its column type does not
change the exported schema, so neither mode sees a change of its stored form: the migration
harness (a frozen-fixture case) and tm-pr-review item 12 catch that. Room writes its build output
only when the schema differs from the committed one, so after a change was built and then reverted
a stale output can remain (a false red in a local build; CI starts from a clean checkout).
scripts/pre-push-check.sh deletes Room's schema build output before its first Gradle step, so the
gate cannot see a stale one; for a manual `./gradlew` build the message names `./gradlew
:data:clean`. --self-test checks that order in scripts/pre-push-check.sh next to this script,
then runs the fixtures.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

USAGE = ("usage: check-room-schema.sh [--repo <dir>] --base <ref> [--head <ref>] "
         "| [--repo <dir>] --check-export-fresh | --self-test")

SCHEMAS = "data/schemas/"
MAIN_SOURCE_RE = re.compile(r"data/src/[^/]+Main/.+")
MIGRATION_DIR_RE = re.compile(r"data/src/commonMain/(?:.+/)?local/database/[^/]+")
TEST_DIR_RE = re.compile(r"data/src/commonTest/(?:.+/)?local/database/[^/]+")
SCHEMA_FILE_RE = re.compile(r"([1-9][0-9]*)\.json")
DATABASE_RE = re.compile(r"@Database\s*\(")
VERSION_ARG_RE = re.compile(r"(?<![A-Za-z0-9_])version\s*=\s*([^,)\n]*)")
FALLBACK = "fallbackToDestructiveMigration"
FALLBACK_RE = re.compile(FALLBACK + r"[A-Za-z0-9_]*")
ONE_DATABASE = "the check supports exactly one database"


class GitError(Exception):
    pass


class Violation(Exception):
    """One or more problems, each a message; reported on stderr with exit 1."""

    def __init__(self, problems):
        super().__init__("; ".join(problems))
        self.problems = problems


def git(repo, args):
    result = subprocess.run(["git", "-C", str(repo), "--literal-pathspecs"] + args,
                            capture_output=True)
    if result.returncode != 0:
        message = result.stderr.decode("utf-8", "replace").strip().splitlines()
        raise GitError(f"git {args[0]} failed: {message[0] if message else 'no message'}")
    return result.stdout


def resolve(repo, ref):
    result = subprocess.run(["git", "-C", str(repo), "rev-parse", "--verify", "--quiet",
                             "--end-of-options", f"{ref}^{{commit}}"], capture_output=True)
    if result.returncode != 0:
        raise GitError(f"'{ref}' is not a commit in {repo}")
    return result.stdout.decode().strip()


class Tree:
    """A committed tree: its paths and, on demand, the bytes of a file."""

    def __init__(self, repo, ref):
        self.repo, self.ref, self.sha = repo, ref, resolve(repo, ref)
        listed = git(repo, ["ls-tree", "-r", "-z", "--name-only", self.sha])
        self.paths = [raw.decode("utf-8", "surrogateescape") for raw in listed.split(b"\0") if raw]
        self.path_set = set(self.paths)

    def read(self, path):
        return git(self.repo, ["cat-file", "blob", f"{self.sha}:{path}"])

    def text(self, path):
        return self.read(path).decode("utf-8", "replace")


def database_version(tree):
    """(version, file) of the single @Database annotation under data/src/*Main/, or raises."""
    found = []
    for path in tree.paths:
        if MAIN_SOURCE_RE.fullmatch(path) and path.endswith(".kt"):
            text = tree.text(path)
            found += [(path, text, m.end()) for m in DATABASE_RE.finditer(text)]
    if not found:
        raise Violation([f"no @Database annotation under data/src/*Main/ at {tree.ref}: cannot apply "
                         "rules (b) to (d) (fail closed)"])
    if len(found) > 1:
        files = ", ".join(sorted({p for p, _, _ in found}))
        raise Violation([f"{len(found)} @Database annotations under data/src/*Main/ at {tree.ref} "
                         f"({files}); {ONE_DATABASE} (fail closed)"])
    path, text, start = found[0]
    depth, end = 1, start
    while end < len(text) and depth:
        depth += {"(": 1, ")": -1}.get(text[end], 0)
        end += 1
    args = VERSION_ARG_RE.findall(text[start:end - 1]) if depth == 0 else []
    if len(args) != 1 or not re.fullmatch(r"[0-9]+", args[0].strip()):
        shown = "; ".join(f"version = {a.strip()}" for a in args) or "no `version = ...` argument"
        raise Violation([f"cannot read the @Database version at {tree.ref} in {path} ({shown}): "
                         "it must be one integer literal, `version = <n>` (fail closed)"])
    return int(args[0].strip()), path


def schema_files(tree):
    """{version: path} of the schema files under data/schemas/<one dir>/, or raises."""
    problems, dirs, files = [], set(), {}
    for path in tree.paths:
        if not path.startswith(SCHEMAS):
            continue
        parts = path[len(SCHEMAS):].split("/")
        match = SCHEMA_FILE_RE.fullmatch(parts[-1]) if len(parts) == 2 else None
        if not match:
            problems.append(f"{path} at {tree.ref} is not a <version>.json schema file in "
                            f"{SCHEMAS}<database>/ (fail closed)")
            continue
        dirs.add(parts[0])
        files[int(match.group(1))] = path
    if len(dirs) > 1:
        problems.append(f"{SCHEMAS} at {tree.ref} has {len(dirs)} schema directories "
                        f"({', '.join(sorted(dirs))}); {ONE_DATABASE} (fail closed)")
    if problems:
        raise Violation(problems)
    return files


def schema_identity(tree, path):
    """(database.version, database.identityHash) of a schema file, or raises Violation."""
    where = f"{path} at {tree.ref}"
    try:
        database = json.loads(tree.read(path).decode("utf-8"))["database"]
    except (UnicodeDecodeError, ValueError):
        raise Violation([f"{where} is not valid JSON (fail closed)"])
    except (KeyError, TypeError):
        raise Violation([f"{where} has no `database` object (fail closed)"])
    version = database.get("version") if isinstance(database, dict) else None
    identity = database.get("identityHash") if isinstance(database, dict) else None
    problems = []
    if not isinstance(version, int) or isinstance(version, bool):
        problems.append(f"{where} has no integer database.version (fail closed)")
    if not isinstance(identity, str) or not identity:
        problems.append(f"{where} has no database.identityHash (fail closed)")
    if problems:
        raise Violation(problems)
    return version, identity


def collect(problems, function, *args):
    try:
        return function(*args)
    except Violation as violation:
        problems += violation.problems
        return None


def check(repo, base_ref, head_ref):
    """Returns the report lines, or raises Violation or GitError."""
    base, head = Tree(repo, base_ref), Tree(repo, head_ref)
    problems, report = [], []

    # Rule (e) first: it needs nothing else to be readable.
    for path in head.paths:
        if not MAIN_SOURCE_RE.fullmatch(path):
            continue
        for number, line in enumerate(head.text(path).split("\n"), start=1):
            for call in sorted(set(FALLBACK_RE.findall(line))):
                problems.append(f"rule (e): {path}, line {number}: {call} would drop the user's "
                                "data when no migration matches; remove it and add a migration")

    base_version = collect(problems, database_version, base)
    head_version = collect(problems, database_version, head)
    base_files = collect(problems, schema_files, base)
    head_files = collect(problems, schema_files, head)
    identities = {}
    for tree, files in ((base, base_files), (head, head_files)):
        for version, path in sorted((files or {}).items()):
            identities[(tree.sha, path)] = collect(problems, schema_identity, tree, path)
    if None in (base_version, head_version, base_files, head_files) or None in identities.values():
        raise Violation(problems)
    (old, _), (new, db_file) = base_version, head_version
    report.append(f"@Database version: {old} at {base_ref}, {new} at {head_ref} ({db_file})")

    # Rule (a): the base's schema files are append-only.
    for version, path in sorted(base_files.items()):
        old_id = identities[(base.sha, path)]
        if path not in head.path_set:
            problems.append(f"rule (a): {path} exists on the base and is deleted; schema files are "
                            "append-only: restore it")
            continue
        new_id = identities[(head.sha, path)]
        if new_id[0] != old_id[0]:
            problems.append(f"rule (a): {path}: database.version changed from {old_id[0]} (base) "
                            f"to {new_id[0]}; schema files are append-only: restore it")
        if new_id[1] != old_id[1]:
            problems.append(f"rule (a): {path}: identityHash changed from {old_id[1]} (base) to "
                            f"{new_id[1]}; an entity change needs a version bump, a new schema "
                            "file and a migration, or must be reverted; restore this file")
        if new_id == old_id:
            report.append(f"  unchanged: {path} (version {new_id[0]}, identityHash {new_id[1]})")

    # Rule (b): the version never goes down.
    if new < old:
        problems.append(f"rule (b): the @Database version goes down from {old} (base) to {new} "
                        f"({db_file}); a database version is never lowered")

    # Rule (c): every step k -> k+1 of a bump has its schema file, migration and test.
    if new > old:
        if new > old + 1:
            problems_before = len(problems)
            report.append(f"  bump {old} -> {new}: checked one step at a time")
        touched = git(repo, ["diff", "--no-ext-diff", "--no-renames", "--name-only", "-z",
                             base.sha, head.sha])
        touched = {raw.decode("utf-8", "surrogateescape") for raw in touched.split(b"\0") if raw}
        sources = {p: head.text(p) for p in head.paths if MIGRATION_DIR_RE.fullmatch(p)}
        tests = {p: head.text(p) for p in head.paths if TEST_DIR_RE.fullmatch(p) and p in touched}
        known = list(head_files.values()) + list(base_files.values())
        schema_dir = known[0].rsplit("/", 1)[0] if known else f"{SCHEMAS}<database>"
        for k in range(old, new):
            name, step = f"MIGRATION_{k}_{k + 1}", f"version {k} -> {k + 1}"
            path = head_files.get(k + 1)
            missing = []
            if path is None or path in base.path_set:
                where = path or f"{schema_dir}/{k + 1}.json"
                missing.append(f"rule (c): {step}: {where} is not added; build the project so Room "
                               "exports it and commit it")
            elif identities[(head.sha, path)][0] != k + 1:
                missing.append(f"rule (c): {step}: {path} has database.version "
                               f"{identities[(head.sha, path)][0]}, not {k + 1}")
            name_re = re.compile(rf"\b(?:val|object)\s+{name}\b")
            defined = sorted(p for p, text in sources.items() if name_re.search(text))
            if not defined:
                missing.append(f"rule (c): {step}: {name} is not defined under "
                               f"data/src/commonMain/.../local/database/ (`val {name} = ...` or "
                               f"`object {name}`); add the migration")
            use_re = re.compile(rf"\b{name}\b")
            named = sorted(p for p, text in tests.items() if use_re.search(text))
            if not named:
                missing.append(f"rule (c): {step}: no test under "
                               "data/src/commonTest/.../local/database/ that this diff touches "
                               f"contains {name}; add the migration's test")
            problems += missing
            if not missing:
                report.append(f"  step {k} -> {k + 1}: {k + 1}.json added (database.version "
                              f"{k + 1}), {name} defined in {', '.join(defined)}, named in "
                              f"{', '.join(named)}")
        if new > old + 1 and len(problems) > problems_before:
            problems.insert(problems_before,
                            f"rule (c): version {old} -> {new}: every step needs its own schema "
                            "file, migration and test (checked one step at a time)")

    # Rule (d): the current version has its schema file.
    current = head_files.get(new)
    if current is None:
        problems.append(f"rule (d): the @Database version is {new} at {head_ref}, but {SCHEMAS} "
                        f"has no {new}.json; build the project so Room exports it and commit it")
    elif identities[(head.sha, current)][0] != new:
        problems.append(f"rule (d): {current} has database.version "
                        f"{identities[(head.sha, current)][0]}, not {new}")

    if problems:
        raise Violation(problems)
    report.append(f"room schema: ok (version {old} -> {new}, {len(head_files)} schema file"
                  f"{'' if len(head_files) == 1 else 's'}, no {FALLBACK} in data/src/*Main/)")
    return report


def check_export_fresh(repo):
    """Returns the report lines, or raises Violation or GitError."""
    status = git(repo, ["status", "--porcelain", "--untracked-files=all", "--", SCHEMAS])
    lines = [line for line in status.decode("utf-8", "replace").splitlines() if line.strip()]
    if lines:
        raise Violation([f"the build changed {SCHEMAS}:"] + [f"  {line}" for line in lines] + [
            "Room rewrote or added a schema file, so the entities no longer match the committed "
            "schema of the current version: a version bump and a migration are missing, or the "
            "entity change must be reverted. Do not commit a rewritten existing file (rule (a) of "
            "scripts/check-room-schema.sh fails on it).",
            "If the entities are as committed (a change was built, then reverted): "
            "Room writes its build output only when the schema differs, so a stale one from the "
            "earlier build can remain. scripts/pre-push-check.sh clears it before its build, so "
            "there a changed file was written by this build; after a manual `./gradlew` build, run "
            "`./gradlew :data:clean`, restore data/schemas/ with `git checkout -- data/schemas` "
            "(and remove an untracked file there), and build again."])
    return [f"schema export: fresh (the build left {SCHEMAS} unchanged)"]


# --- self-test ------------------------------------------------------------------------------

FIXTURES = "check-room-schema-fixtures"
FIXTURE_SUFFIX = ".fixture"


def fixture_path(rel):
    """Fixture trees spell Kotlin files as `<name>.kt.fixture`, so no Gradle source set, Detekt or
    IDE takes them for sources; the suffix is dropped when the tree is written."""
    parts = list(rel.parts)
    if parts[-1].endswith(FIXTURE_SUFFIX):
        parts[-1] = parts[-1][:-len(FIXTURE_SUFFIX)]
    return Path(*parts)


def self_git(repo, *args):
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=self-test",
                    "-c", "user.email=self-test@example.invalid", "-c", "commit.gpgsign=false",
                    "-c", "core.hooksPath=/dev/null"] + list(args),
                   check=True, capture_output=True)


def write_tree(repo, tree):
    for child in repo.iterdir():
        if child.name != ".git":
            shutil.rmtree(child) if child.is_dir() else child.unlink()
    if tree.is_dir():
        for src in sorted(p for p in tree.rglob("*") if p.is_file()):
            dst = repo / fixture_path(src.relative_to(tree))
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(src.read_bytes())


def run_fixture(entry, fixture):
    """`base/` (the first commit) and `head/` (a second commit on top of it, or with
    `setup: worktree` the uncommitted working tree) trees, each optional, and `expect`: `exit: N`,
    any number of `stdout: <text>` and `stderr: <text>` lines that the output must contain and
    `absent: <text>` lines that neither may contain, optional `args: ...` (BASE is the base commit;
    default `--base BASE`; `args:` alone is no arguments), optional `setup: no-repo` (the --repo
    directory is not a git repository) or `setup: worktree`."""
    expect = {"exit": None, "stdout": [], "stderr": [], "absent": [], "args": None, "setup": None}
    for line in (fixture / "expect").read_text(encoding="utf-8").splitlines():
        key, _, value = line.partition(": ")
        key = key.rstrip(":")
        if key == "exit":
            expect["exit"] = int(value)
        elif key in ("stdout", "stderr", "absent"):
            expect[key].append(value)
        elif key in ("args", "setup"):
            expect[key] = value
        elif line.strip():
            raise ValueError(f"{fixture.name}/expect: unknown line '{line}'")
    if expect["exit"] is None:
        raise ValueError(f"{fixture.name}/expect: no 'exit:' line")
    if expect["setup"] not in (None, "no-repo", "worktree"):
        raise ValueError(f"{fixture.name}/expect: unknown setup '{expect['setup']}'")
    with tempfile.TemporaryDirectory(prefix="tm-room-schema-") as tmp:
        repo = Path(tmp)
        sha = ""
        if expect["setup"] != "no-repo":
            self_git(repo, "init", "-q")
            write_tree(repo, fixture / "base")
            self_git(repo, "add", "-A")
            self_git(repo, "commit", "-q", "--allow-empty", "-m", "base")
            sha = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], check=True,
                                 capture_output=True, text=True).stdout.strip()
            write_tree(repo, fixture / "head")
            if expect["setup"] != "worktree":
                self_git(repo, "add", "-A")
                self_git(repo, "commit", "-q", "--allow-empty", "-m", "head")
        args = (expect["args"] if expect["args"] is not None else "--base BASE").split()
        args = [sha if a == "BASE" else a for a in args]
        env = dict(os.environ, LC_ALL="C")
        result = subprocess.run(["bash", str(entry), "--repo", str(repo)] + args,
                                capture_output=True, text=True, env=env)
        out, err = (s.replace(sha, "<base>") if sha else s for s in (result.stdout, result.stderr))
        out, err = out.replace(str(repo), "<repo>"), err.replace(str(repo), "<repo>")
    errors = []
    if result.returncode != expect["exit"]:
        errors.append(f"exit {result.returncode}, expected {expect['exit']}")
    errors += [f"stdout is missing: {s}" for s in expect["stdout"] if s not in out]
    errors += [f"stderr is missing: {s}" for s in expect["stderr"] if s not in err]
    errors += [f"output contains: {s}" for s in expect["absent"] if s in out + err]
    return errors, result.returncode, out + err


GATE_FULL_BLOCK = 'if [ "$DECISION" = full ]; then'
GATE_CLEAR = 'rm -rf "$REPO_ROOT/data/build/intermediates/room/schemas"'


def gate_clear_problems(gate_text):
    """The gate's full block must delete Room's schema build output before its first Gradle step:
    lint, the tests and assembleDebug all run :data:copyRoomSchemas, which would copy a stale
    output from an earlier, reverted entity change over data/schemas/ (a false red in "room schema
    export fresh"). Returns the problems, empty when the order is right."""
    lines = [line.strip() for line in gate_text.splitlines()]
    if GATE_FULL_BLOCK not in lines:
        return [f"no line '{GATE_FULL_BLOCK}' in scripts/pre-push-check.sh"]
    block = lines[lines.index(GATE_FULL_BLOCK) + 1:]
    code = [line for line in block if line and not line.startswith("#")]
    gradle = next((n for n, line in enumerate(code) if "./gradlew" in line), None)
    if gradle is None:
        return ["the full block of scripts/pre-push-check.sh runs no ./gradlew step"]
    if GATE_CLEAR not in code[:gradle]:
        return [f"the full block of scripts/pre-push-check.sh does not run `{GATE_CLEAR}` before "
                f"its first Gradle step ({code[gradle]})"]
    return []


def self_test(script_dir):
    failed = total = 0
    gate = script_dir / "pre-push-check.sh"
    print("--- gate order (scripts/pre-push-check.sh next to this script)")
    try:
        errors = gate_clear_problems(gate.read_text(encoding="utf-8"))
    except OSError as e:
        errors = [f"cannot read {gate}: {e}"]
    total += 1
    failed += bool(errors)
    print(f"    {'FAIL' if errors else 'ok  '} gate-clears-room-output-before-gradle")
    print("".join(f"         SELF-TEST FAIL: {e}\n" for e in errors), end="")
    fixtures = script_dir / FIXTURES
    entry = script_dir / "check-room-schema.sh"
    print(f"--- fixtures ({FIXTURES}/, scripts/check-room-schema.sh in a temporary git repo)")
    cases = sorted(p for p in fixtures.iterdir() if p.is_dir()) if fixtures.is_dir() else []
    for fixture in cases:
        total += 1
        try:
            errors, code, output = run_fixture(entry, fixture)
        except (OSError, ValueError, subprocess.CalledProcessError) as e:
            errors, code, output = [f"fixture error: {e}"], "-", ""
        failed += bool(errors)
        print(f"    {'FAIL' if errors else 'ok  '} {fixture.name}: exit {code}")
        print("".join(f"         | {line}\n" for line in output.splitlines()), end="")
        print("".join(f"         SELF-TEST FAIL: {e}\n" for e in errors), end="")
    if not cases:
        total += 1
        failed += 1
        print(f"    FAIL no fixtures found in {fixtures}")
    print(f"check-room-schema self-test: {total - failed}/{total} cases passed")
    return 1 if failed else 0


def main(argv):
    script_dir = Path(__file__).resolve().parent
    if argv == ["--self-test"]:
        return self_test(script_dir)
    repo, base, head, fresh, args = Path.cwd(), None, "HEAD", False, list(argv)
    ok = bool(args)
    while args:
        option = args.pop(0)
        if option in ("--repo", "--base", "--head") and args and args[0] \
                and not args[0].startswith("-"):
            value = args.pop(0)
            if option == "--repo":
                repo = Path(value)
            elif option == "--base":
                base = value
            else:
                head = value
        elif option == "--check-export-fresh":
            fresh = True
        else:
            ok = False
            break
    if not ok or fresh == (base is not None) or (fresh and head != "HEAD"):
        print(f"{USAGE} (got {' '.join(argv) or 'no arguments'})", file=sys.stderr)
        return 2
    name = "schema export" if fresh else "room schema"
    try:
        report = check_export_fresh(repo) if fresh else check(repo, base, head)
    except GitError as error:
        print(f"check-room-schema: {error}", file=sys.stderr)
        return 2
    except Violation as violation:
        for problem in violation.problems:
            print(f"check-room-schema: {problem}", file=sys.stderr)
        if fresh:
            count = len([p for p in violation.problems if p.startswith("  ")])
            summary = f"{count} file{'' if count == 1 else 's'} changed by the build"
        else:
            count = len(violation.problems)
            summary = f"{count} problem{'' if count == 1 else 's'}"
        print(f"{name}: FAILED ({summary})", file=sys.stderr)
        return 1
    print("\n".join(report))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
