#!/usr/bin/env python3
"""Self-test of the gate's iOS scope filter.

Run through scripts/check-ios-scope.sh (the entry point). Standard library only, so it runs on
the stock python3 of macOS and ubuntu-latest without installing anything.

  check-ios-scope.sh --self-test                  test the committed scripts/pre-push-check.sh
                                                  against the committed
                                                  scripts/build-kmp-framework.sh
  check-ios-scope.sh --self-test --script <file>  test another copy of the gate script (used
                                                  to show the test going red on a broken
                                                  version)
  check-ios-scope.sh --self-test --build-script <file>
                                                  take BUILD_FILES from another copy of the
                                                  framework build script (same use)

What it does, per run:
  1. Extracts, from the script itself, the lines from `# >>> iOS scope: ... (begin) >>>` to
     `# <<< iOS scope: ... (end) <<<`. It fails when a marker is missing, appears more than
     once, or the end marker comes before the begin marker; the fixtures in
     fixtures/extractor/ show each of these failing. The block is never retyped here.
  2. Extracts the entries of BUILD_FILES, the framework inputs that the build script hashes,
     from the build script itself (never a retyped list). It fails when the assignment is
     missing, appears more than once, is not one line `BUILD_FILES="<paths>"`, contains `$`, a
     backtick or a backslash, yields no entries, or yields an entry that is not a plain
     relative file path (glob characters, a leading `/` or `./`, a `.` or `..` component, an
     empty component such as a trailing `/`); the fixtures in fixtures/build-files-extractor/
     show each of these failing.
  3. Runs every case in fixtures/cases/ in its own scratch git repository: a base commit, the
     ref origin/main pointing at it, and a branch commit with the case's changes. The block
     runs as the gate runs it (`set -uo pipefail`, bash from PATH) in a separate bash process
     whose working directory is the repository root, and prints its variables to a file
     outside the repository.
  4. Checks TOUCHES_IOS_OR_SHARED, BASE_REF (the merge-base, or HEAD~1 with the merge-base
     warning when there is none), the "not exact" warning and its reason (with the fail-safe
     line, or neither), the final CHANGED_FILES, an empty stderr and exit 0.
  5. Runs every BUILD_FILES entry through the block with scope_of_paths() (one case per entry,
     labelled build-files/<entry>) and expects TOUCHES_IOS_OR_SHARED=true: a file the build
     script hashes must make the gate run its iOS steps. It compares two lists of paths, not
     what the iOS build actually reads.

Fixture format, fixtures/cases/<name>/:
  changes  (optional) one change per line, fields separated by a tab: `A <path>`, `M <path>`,
           `D <path>` or `R <old path> <new path>`. The base commit holds every path that is
           modified, deleted or renamed. No changes: the branch commit is empty.
  expect   lines `key: value`; `#` starts a comment line.
             touches: true|false
             warning: none | <the exact reason>; {BASE} is the base the block must use and
                      {GIT_DIFF_ERROR} the first stderr line of that `git diff`, run here
             files:   one line per expected CHANGED_FILES entry, in git's order, or the single
                      line `files: (none)`
             setup:   (optional) no-merge-base (origin/main is an unrelated root commit),
                      no-merge-base-root-commit (also: the branch commit has no parent),
                      git-diff-fails (the branch commit's root tree object is corrupt),
                      mktemp-fails (a stub `mktemp` that exits 1 comes first on PATH)
  Paths in `changes` and `files` may use the escapes \\n (newline), \\t (tab) and \\\\.

Fixture format, fixtures/extractor/<name>/ and fixtures/build-files-extractor/<name>/: the
input (`script.sh`, a gate script, or `build-kmp-framework.sh`, a framework build script) and
`expect`, one line `error: none` or `error: <text the error must contain>`.

The groups of checks are listed in GROUPS; a later check of the filter is a new group that
uses scope_of_paths(), as group_build_files does.
"""

import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

BEGIN_RE = re.compile(r"^# >>> iOS scope: .+ \(begin\) >>>$")
END_RE = re.compile(r"^# <<< iOS scope: .+ \(end\) <<<$")
BUILD_FILES_ASSIGN_RE = re.compile(r"(?<![A-Za-z0-9_])BUILD_FILES\+?=")
BUILD_FILES_LINE_RE = re.compile(r'^BUILD_FILES="([^"]*)"[ \t]*$')
WARNING_PREFIX = "Warning: the changed-file list for the iOS scope is not exact: "
FAIL_SAFE_LINE = "iOS/shared checks required: true (fail-safe)"
MERGE_BASE_LINE = "Warning: could not find merge-base with origin/main; checking all changes vs HEAD~1"
SETUPS = ("no-merge-base", "no-merge-base-root-commit", "git-diff-fails", "mktemp-fails")
STEP_TIMEOUT = 60
GIT_CONFIG = ("-c", "user.name=ios-scope-self-test", "-c", "user.email=self-test@example.invalid",
              "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "-c", "gc.auto=0",
              "-c", "init.defaultBranch=work")
# Printed after the block, NUL-separated, to $IOS_SCOPE_SELFTEST_OUT.
REPORT = ('printf \'%s\\0\' "${TOUCHES_IOS_OR_SHARED-<unset>}" "${BASE_REF-<unset>}" '
          '"${CHANGED_FILES-<unset>}" "${IOS_PATHS-<unset>}" "${IOS_PATHS_EXCLUDED-<unset>}" '
          '>"$IOS_SCOPE_SELFTEST_OUT"\n')


class ExtractError(Exception):
    pass


class FixtureError(Exception):
    pass


def extract(path):
    """Returns (block text, first line number, last line number) of the marked block."""
    try:
        lines = path.read_text(encoding="utf-8").split("\n")
    except OSError as e:
        raise ExtractError(f"cannot read {path}: {e.strerror}")
    begins = [i for i, line in enumerate(lines) if BEGIN_RE.match(line)]
    ends = [i for i, line in enumerate(lines) if END_RE.match(line)]
    for name, found in (("begin", begins), ("end", ends)):
        if not found:
            raise ExtractError(f"{name} marker not found")
        if len(found) > 1:
            where = ", ".join(str(i + 1) for i in found)
            raise ExtractError(f"{name} marker appears {len(found)} times (lines {where})")
    if ends[0] < begins[0]:
        raise ExtractError(f"end marker (line {ends[0] + 1}) comes before the begin marker "
                           f"(line {begins[0] + 1})")
    return "\n".join(lines[begins[0]:ends[0] + 1]) + "\n", begins[0] + 1, ends[0] + 1


def extract_build_files(path):
    """Returns (entries, line number) of the build script's BUILD_FILES assignment."""
    try:
        lines = path.read_text(encoding="utf-8").split("\n")
    except OSError as e:
        raise ExtractError(f"cannot read {path}: {e.strerror}")
    # Any non-comment line that assigns BUILD_FILES (also `export BUILD_FILES=`, `+=`, an
    # assignment after `;`) counts, so a second assignment can't hide behind another form.
    found = [i for i, line in enumerate(lines)
             if not line.lstrip().startswith("#") and BUILD_FILES_ASSIGN_RE.search(line)]
    if not found:
        raise ExtractError("BUILD_FILES assignment not found")
    if len(found) > 1:
        where = ", ".join(str(i + 1) for i in found)
        raise ExtractError(f"BUILD_FILES is assigned {len(found)} times (lines {where})")
    number = found[0] + 1
    match = BUILD_FILES_LINE_RE.match(lines[found[0]])
    if not match:
        raise ExtractError(f"BUILD_FILES (line {number}) is not a single double-quoted one-line "
                           f"value BUILD_FILES=\"<paths>\": '{lines[found[0]]}'")
    value = match.group(1)
    expansions = sorted(set(c for c in value if c in "$`\\"))
    if expansions:
        raise ExtractError(f"BUILD_FILES (line {number}) contains an expansion or escape "
                           f"({' '.join(expansions)}), so its entries are not literal")
    entries = value.split()
    if not entries:
        raise ExtractError(f"BUILD_FILES (line {number}) yields no entries")
    for entry in entries:
        problem = None
        if any(c in entry for c in "*?[]{}~"):
            problem = "has glob or expansion characters"
        elif entry.startswith("/"):
            problem = "starts with /"
        elif entry.startswith("./"):
            problem = "starts with ./"
        elif entry.endswith("/"):
            problem = "ends with /"
        elif ".." in entry.split("/"):
            problem = "has a .. component"
        elif any(part in ("", ".") for part in entry.split("/")):
            problem = "has an empty or . component"
        if problem:
            raise ExtractError(f"BUILD_FILES (line {number}) entry '{entry}' {problem}, so it is "
                               "not a plain relative file path")
    return entries, number


# --- Scratch repositories ------------------------------------------------------------------

def _env(tmp):
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null",
               GIT_CEILING_DIRECTORIES=str(tmp))
    return env


def _git(repo, env, *args, check=True):
    result = subprocess.run(["git", *GIT_CONFIG, *args], cwd=repo, env=env, capture_output=True,
                            stdin=subprocess.DEVNULL, timeout=STEP_TIMEOUT)
    if check and result.returncode != 0:
        raise FixtureError(f"git {' '.join(args)} failed: "
                           f"{result.stderr.decode('utf-8', 'replace').strip()}")
    return result


def _write(repo, path, text, append=False):
    target = repo / path
    target.parent.mkdir(parents=True, exist_ok=True)
    with open(target, "a" if append else "w", encoding="utf-8") as f:
        f.write(text)


def build_repo(tmp, changes, setup=""):
    """Builds tmp/repo: base commit, origin/main, branch commit with the changes."""
    repo = tmp / "repo"
    env = _env(tmp)
    repo.mkdir()
    _git(repo, env, "init", "-q")
    _write(repo, "seed.txt", "seed\n")
    for op, *paths in changes:
        if op in ("M", "D", "R"):
            _write(repo, paths[0], f"base {paths[0]}\n")
    _git(repo, env, "add", "-A")
    _git(repo, env, "commit", "-q", "-m", "base")
    _git(repo, env, "update-ref", "refs/remotes/origin/main", "HEAD")
    for op, *paths in changes:
        if op == "A":
            _write(repo, paths[0], f"added {paths[0]}\n")
        elif op == "M":
            _write(repo, paths[0], "changed\n", append=True)
        elif op == "D":
            _git(repo, env, "rm", "-q", "--", paths[0])
        elif op == "R":
            (repo / paths[1]).parent.mkdir(parents=True, exist_ok=True)
            _git(repo, env, "mv", "--", paths[0], paths[1])
    _git(repo, env, "add", "-A")
    _git(repo, env, "commit", "-q", "--allow-empty", "-m", "branch")

    if setup == "no-merge-base":
        empty_tree = _git(repo, env, "mktree").stdout.decode().strip()
        orphan = _git(repo, env, "commit-tree", empty_tree, "-m", "unrelated").stdout.decode().strip()
        _git(repo, env, "update-ref", "refs/remotes/origin/main", orphan)
    elif setup == "no-merge-base-root-commit":
        root = _git(repo, env, "commit-tree", "HEAD^{tree}", "-m", "branch, no parent")
        _git(repo, env, "update-ref", "refs/heads/work", root.stdout.decode().strip())
    elif setup == "git-diff-fails":
        # Overwrites the loose object of the branch commit's root tree: `git merge-base` reads
        # only commit objects and still works, `git diff --name-only` must read the tree.
        tree = _git(repo, env, "rev-parse", "HEAD^{tree}").stdout.decode().strip()
        base_tree = _git(repo, env, "rev-parse", "origin/main^{tree}").stdout.decode().strip()
        if tree == base_tree:
            raise FixtureError("setup git-diff-fails needs changes (the trees are equal)")
        obj = repo / ".git" / "objects" / tree[:2] / tree[2:]
        os.chmod(obj, stat.S_IRUSR | stat.S_IWUSR)
        obj.write_bytes(b"not a zlib stream")
    return repo, env


def expected_base(repo, env):
    """The base the block must use, and the first stderr line of its `git diff` (or "")."""
    merge_base = _git(repo, env, "merge-base", "HEAD", "origin/main", check=False)
    base = merge_base.stdout.decode().strip() if merge_base.returncode == 0 else "HEAD~1"
    diff = _git(repo, env, "diff", "--no-ext-diff", "--no-renames", "--name-only", "-z",
                "--end-of-options", base, "HEAD", check=False)
    error = ""
    if diff.returncode != 0:
        error = (diff.stderr.decode("utf-8", "replace").split("\n") + [""])[0]
    return base, error


def run_block(block, bash, repo, env, tmp, setup=""):
    """Runs the block in repo; returns (exit code, stdout, stderr, variables or None)."""
    out = tmp / "vars"
    runner = tmp / "runner.sh"
    runner.write_text("set -uo pipefail\n" + block + REPORT, encoding="utf-8")
    env = dict(env, IOS_SCOPE_SELFTEST_OUT=str(out))
    if setup == "mktemp-fails":
        stub_dir = tmp / "stub-bin"
        stub_dir.mkdir()
        stub = stub_dir / "mktemp"
        stub.write_text("#!/bin/sh\necho 'mktemp: stub failure' >&2\nexit 1\n", encoding="utf-8")
        stub.chmod(0o755)
        env["PATH"] = f"{stub_dir}{os.pathsep}{env.get('PATH', '')}"
    result = subprocess.run([bash, str(runner)], cwd=repo, env=env, capture_output=True,
                            timeout=STEP_TIMEOUT)
    variables = None
    if out.exists():
        fields = out.read_bytes().decode("utf-8", "replace").split("\0")
        if len(fields) == 6:
            variables = dict(zip(("touches", "base_ref", "changed_files", "ios_paths",
                                  "ios_paths_excluded"), fields[:5]))
    return (result.returncode, result.stdout.decode("utf-8", "replace"),
            result.stderr.decode("utf-8", "replace"), variables)


def scope_of_paths(block, bash, paths):
    """TOUCHES_IOS_OR_SHARED ("true"/"false") for a branch that adds the given paths."""
    with tempfile.TemporaryDirectory(prefix="ios-scope-") as t:
        tmp = Path(t)
        repo, env = build_repo(tmp, [("A", p) for p in paths])
        code, _, stderr, variables = run_block(block, bash, repo, env, tmp)
        if code != 0 or variables is None:
            raise FixtureError(f"the block failed (exit {code}): {stderr.strip()}")
        return variables["touches"]


# --- Fixtures ------------------------------------------------------------------------------

def _unescape(text, where):
    def repl(m):
        return {"n": "\n", "t": "\t", "\\": "\\"}[m.group(1)]
    if re.search(r"\\(?![nt\\])", text):
        raise FixtureError(f"{where}: unknown escape in '{text}'")
    return re.sub(r"\\([nt\\])", repl, text)


def load_case(fixture):
    changes = []
    changes_file = fixture / "changes"
    if changes_file.exists():
        for n, line in enumerate(changes_file.read_text(encoding="utf-8").splitlines(), 1):
            if not line:
                continue
            op, *paths = line.split("\t")
            paths = [_unescape(p, f"changes line {n}") for p in paths]
            if (op, len(paths)) not in (("A", 1), ("M", 1), ("D", 1), ("R", 2)):
                raise FixtureError(f"changes line {n}: '{line}' is not A, M, D <path> or R <old> <new>")
            changes.append((op, *paths))
    case = {"touches": None, "warning": None, "files": None, "setup": ""}
    for n, line in enumerate((fixture / "expect").read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        key, sep, value = line.partition(": ")
        if not sep or key not in case:
            raise FixtureError(f"expect line {n}: '{line}' is not a known `key: value`")
        if key == "files":
            case["files"] = case["files"] or []
            if value != "(none)":
                case["files"].append(_unescape(value, f"expect line {n}"))
        else:
            case[key] = value
    if case["touches"] not in ("true", "false"):
        raise FixtureError("expect needs `touches: true` or `touches: false`")
    if case["warning"] is None or case["files"] is None:
        raise FixtureError("expect needs a `warning:` and at least one `files:` line")
    if case["setup"] and case["setup"] not in SETUPS:
        raise FixtureError(f"unknown setup '{case['setup']}'")
    return changes, case


def run_case(fixture, block, bash):
    """Returns (errors, description, output lines)."""
    changes, case = load_case(fixture)
    with tempfile.TemporaryDirectory(prefix="ios-scope-") as t:
        tmp = Path(t)
        repo, env = build_repo(tmp, changes, case["setup"])
        base, diff_error = expected_base(repo, env)
        code, stdout, stderr, got = run_block(block, bash, repo, env, tmp, case["setup"])

    lines = stdout.splitlines()
    output = [f"out> {line}" for line in lines] + [f"err> {line}" for line in stderr.splitlines()]
    if code != 0 or got is None:
        return [f"the block failed: exit {code}, variables {'missing' if got is None else 'read'}"], "", output
    errors = []
    if got["touches"] != case["touches"]:
        errors.append(f"TOUCHES_IOS_OR_SHARED expected {case['touches']}, got {got['touches']}")
    if got["base_ref"] != base:
        errors.append(f"BASE_REF expected {base}, got {got['base_ref']}")
    want_mb_line = base == "HEAD~1"
    if (MERGE_BASE_LINE in lines) != want_mb_line:
        errors.append(f"merge-base warning expected {'present' if want_mb_line else 'absent'}, "
                      f"got {'present' if not want_mb_line else 'absent'}")
    warnings = [line[len(WARNING_PREFIX):] for line in lines if line.startswith(WARNING_PREFIX)]
    got_warning = "none" if not warnings else " | ".join(warnings)
    want_warning = case["warning"]
    if "{GIT_DIFF_ERROR}" in want_warning and not diff_error:
        errors.append("the fixture expects a git diff error, but git diff succeeded here")
    want_warning = want_warning.replace("{BASE}", base).replace("{GIT_DIFF_ERROR}", diff_error)
    if got_warning != want_warning:
        errors.append(f"warning expected '{want_warning}', got '{got_warning}'")
    has_fail_safe = any(line.strip() == FAIL_SAFE_LINE for line in lines)
    if has_fail_safe != bool(warnings):
        errors.append(f"fail-safe line {'present' if has_fail_safe else 'absent'} with "
                      f"{len(warnings)} 'not exact' warnings")
    want_files = "\n".join(case["files"])
    if got["changed_files"] != want_files:
        errors.append(f"CHANGED_FILES expected {want_files!r}, got {got['changed_files']!r}")
    if stderr:
        errors.append(f"stderr expected empty, got {stderr.strip()!r}")
    desc = (f"touches={got['touches']}, warning: {got_warning}, "
            f"{len(case['files'])} file(s)" + (f", setup {case['setup']}" if case["setup"] else ""))
    return errors, desc, output


def run_extractor_fixture(fixture, extractor=extract, input_name="script.sh"):
    want = (fixture / "expect").read_text(encoding="utf-8").strip()
    if not want.startswith("error: "):
        raise FixtureError("expect must be one line `error: none` or `error: <text>`")
    want = want[len("error: "):]
    try:
        result = extractor(fixture / input_name)
        got = None
    except ExtractError as e:
        got = str(e)
    if want == "none":
        if got is not None:
            return [f"extraction failed: {got}"], "", []
        if extractor is extract_build_files:
            return [], f"extracted {len(result[0])} entries", []
        return [], "extracted", []
    if got is None:
        return [f"extraction succeeded, expected an error containing '{want}'"], "", []
    if want not in got:
        return [f"error expected to contain '{want}', got '{got}'"], "", []
    return [], f"failed as intended: {got}", []


# --- Groups --------------------------------------------------------------------------------

def run_build_file(entry, block, bash, build_script):
    touches = scope_of_paths(block, bash, [entry])
    if touches != "true":
        return [f"the filter returned TOUCHES_IOS_OR_SHARED={touches} for '{entry}': "
                f"{build_script} hashes this file (BUILD_FILES), but the gate would skip the "
                "iOS steps for a change to it"], "", []
    return [], "touches=true", []


def group_extractor(fixtures, block, bash, build):
    for fixture in sorted(p for p in (fixtures / "extractor").iterdir() if p.is_dir()):
        yield f"extractor/{fixture.name}", lambda f=fixture: run_extractor_fixture(f)


def group_build_files_extractor(fixtures, block, bash, build):
    for fixture in sorted(p for p in (fixtures / "build-files-extractor").iterdir() if p.is_dir()):
        yield (f"build-files-extractor/{fixture.name}",
               lambda f=fixture: run_extractor_fixture(f, extract_build_files,
                                                       "build-kmp-framework.sh"))


def group_cases(fixtures, block, bash, build):
    for fixture in sorted(p for p in (fixtures / "cases").iterdir() if p.is_dir()):
        yield f"cases/{fixture.name}", lambda f=fixture: run_case(f, block, bash)


def group_build_files(fixtures, block, bash, build):
    build_script, entries = build
    for entry in entries:
        yield f"build-files/{entry}", lambda e=entry: run_build_file(e, block, bash, build_script)


GROUPS = (group_extractor, group_build_files_extractor, group_cases, group_build_files)


def _report(label, errors, desc, output):
    if errors:
        print(f"FAIL {label}: " + "; ".join(errors))
        print("".join(f"    {line}\n" for line in output), end="")
        return 1
    print(f"ok   {label}" + (f": {desc}" if desc else ""))
    return 0


def _shown(path, script_dir):
    try:
        return path.relative_to(script_dir.parent)
    except ValueError:
        return path


def self_test(script_dir, script, build_script):
    fixtures = script_dir / "check-ios-scope-fixtures"
    missing = [tool for tool in ("bash", "git") if shutil.which(tool) is None]
    if missing:
        print(f"check-ios-scope: FAILED, not found on PATH: {', '.join(missing)} "
              "(the block under test needs them)", file=sys.stderr)
        return 1
    bash = shutil.which("bash")
    bash_version = subprocess.run([bash, "-c", "echo $BASH_VERSION"], capture_output=True,
                                  text=True).stdout.strip()
    git_version = subprocess.run(["git", "--version"], capture_output=True,
                                 text=True).stdout.strip()
    try:
        block, first, last = extract(script)
    except ExtractError as e:
        print(f"check-ios-scope: FAILED, cannot extract the iOS scope block from {script}: {e}")
        return 1
    try:
        build_files, build_files_line = extract_build_files(build_script)
    except ExtractError as e:
        print(f"check-ios-scope: FAILED, cannot extract BUILD_FILES from {build_script}: {e}")
        return 1
    shown = _shown(script, script_dir)
    shown_build = _shown(build_script, script_dir)
    with tempfile.TemporaryDirectory(prefix="ios-scope-") as t:
        tmp = Path(t)
        try:
            repo, env = build_repo(tmp, [])
        except FixtureError as e:
            print(f"check-ios-scope: FAILED, cannot build a scratch repository: {e}")
            return 1
        _, _, _, probe = run_block(block, bash, repo, env, tmp)
    probe = probe or {"ios_paths": "<block failed>", "ios_paths_excluded": "<block failed>"}
    print(f"--- iOS scope block extracted from {shown} (lines {first}-{last}): "
          f"IOS_PATHS={probe['ios_paths']} IOS_PATHS_EXCLUDED={probe['ios_paths_excluded']}; "
          f"{len(build_files)} BUILD_FILES entries from {shown_build} (line {build_files_line}); "
          f"run with {bash} (bash {bash_version}), {git_version}")

    total = failed = 0
    for group in GROUPS:
        for label, run in group(fixtures, block, bash, (shown_build, build_files)):
            total += 1
            try:
                errors, desc, output = run()
            except (OSError, FixtureError, subprocess.TimeoutExpired) as e:
                errors, desc, output = [f"fixture error: {e}"], "", []
            failed += _report(label, errors, desc, output)
    print(f"ios-scope self-test: {total - failed}/{total} cases passed")
    return 1 if failed or total == 0 else 0


def main(argv):
    script_dir = Path(__file__).resolve().parent
    script = script_dir / "pre-push-check.sh"
    build_script = script_dir / "build-kmp-framework.sh"
    usage = "usage: check-ios-scope.sh --self-test [--script <file>] [--build-script <file>]"
    want_self_test = False
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--self-test":
            want_self_test = True
        elif arg == "--script" and args:
            script = Path(args.pop(0)).resolve()
        elif arg == "--build-script" and args:
            build_script = Path(args.pop(0)).resolve()
        else:
            print(f"{usage} (got '{arg}')", file=sys.stderr)
            return 2
    if not want_self_test:
        print(usage, file=sys.stderr)
        return 2
    return self_test(script_dir, script, build_script)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
