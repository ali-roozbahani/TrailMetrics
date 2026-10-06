#!/usr/bin/env python3
"""Coverage floor ratchet: the Kover floors in config/kover-floors.properties may only go up.

Run through scripts/check-kover-floors.sh (the entry point). Standard library only, so it runs on
the stock python3 of macOS and ubuntu-latest without installing anything.

  check-kover-floors.sh [--repo <dir>] --base <ref>   compare the working tree with <ref>
  check-kover-floors.sh --self-test                    run the fixtures

The floors file: one `<module>=<integer>` line per module, the key being the module's directory
name, the value an integer from 0 to 100 without leading zeros; spaces or tabs around `=` are
allowed. Blank lines and lines starting with `#` are ignored. Anything else (no `=`, a colon or
any other character in a key, a blank value, a duplicate key, a backslash continuation) fails.

A module with a Kover floor is every `build.gradle.kts` in the working tree (tracked, or untracked
and not ignored) whose text contains `config/kover-floors.properties`; its key is the name of the
directory it is in. Every such module needs an entry and every entry needs such a module.

The base floors are the base commit's floors file. A base without that file (the commit before
the floors moved into it) gives them from the `minBound(<n>)` literal of each of its
`build.gradle.kts` files instead; a base with neither fails.

Fails (exit 1, one message per problem on stderr): an invalid floors file, a floor lower than the
same key on the base, a module without an entry, an entry without a module, two modules with the
same directory name, a root build.gradle.kts that reads the file. Passes (exit 0, a report on
stdout): every floor equal or higher, a new module with a floor, and a key that is gone together
with its module. Exit 2 for a usage or git error, never a pass.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

USAGE = "usage: check-kover-floors.sh [--repo <dir>] --base <ref> | --self-test"

FLOORS_FILE = "config/kover-floors.properties"
BUILD_FILE = "build.gradle.kts"

ENTRY_RE = re.compile(r"([A-Za-z0-9][A-Za-z0-9._-]*)[ \t]*=[ \t]*(.*?)[ \t]*")
VALUE_RE = re.compile(r"0|[1-9][0-9]?|100")
MIN_BOUND_RE = re.compile(r"\bminBound\(\s*([0-9]+)\s*\)")


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


def parse_floors(data, where):
    """Returns {key: floor} from the bytes of a floors file, or raises Violation."""
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        raise Violation([f"{where}: not valid UTF-8"])
    floors, problems = {}, []
    for number, line in enumerate(text.split("\n"), start=1):
        line = line[:-1] if line.endswith("\r") else line
        if not line.strip() or line.startswith("#"):
            continue
        match = ENTRY_RE.fullmatch(line)
        if not match:
            problems.append(f"{where}, line {number}: unknown syntax {line!r} "
                            "(expected `<module>=<integer>` or a `#` comment)")
            continue
        key, value = match.group(1), match.group(2)
        if not value:
            problems.append(f"{where}, line {number}: `{key}` has a blank value")
        elif not VALUE_RE.fullmatch(value):
            problems.append(f"{where}, line {number}: `{key}` is {value!r}, "
                            "not an integer from 0 to 100")
        elif key in floors:
            problems.append(f"{where}, line {number}: duplicate key `{key}`")
        else:
            floors[key] = int(value)
    if problems:
        raise Violation(problems)
    return floors


def module_key(path):
    """The key of a build file: the name of its directory (None for the root build file)."""
    parent = Path(path).parent
    return None if str(parent) in ("", ".") else parent.name


def keyed(files, where):
    """{key: path} for the build files, or raises Violation on a root file or a repeated key."""
    modules, problems = {}, []
    for path in sorted(files):
        key = module_key(path)
        if key is None:
            problems.append(f"{where}: the root {BUILD_FILE} reads {FLOORS_FILE}; only modules "
                            "can have a floor (the key is the module's directory name)")
        elif key in modules:
            problems.append(f"{where}: {modules[key]} and {path} have the same directory name "
                            f"`{key}`, so they cannot have separate keys")
        else:
            modules[key] = path
    if problems:
        raise Violation(problems)
    return modules


def working_tree_modules(repo):
    """{key: path} of the working tree's build files that read the floors file."""
    listed = git(repo, ["ls-files", "-z", "--cached", "--others", "--exclude-standard"])
    files = []
    for raw in listed.split(b"\0"):
        path = raw.decode("utf-8", "surrogateescape")
        if Path(path).name != BUILD_FILE:
            continue
        full = Path(repo) / path
        if full.is_file() and FLOORS_FILE.encode() in full.read_bytes():
            files.append(path)
    return keyed(files, "working tree")


def base_files(repo, sha):
    listed = git(repo, ["ls-tree", "-r", "-z", "--name-only", sha])
    return [raw.decode("utf-8", "surrogateescape") for raw in listed.split(b"\0") if raw]


def base_floors(repo, ref, sha):
    """(floors, source line) of the base commit, or raises Violation when it has none."""
    files = base_files(repo, sha)
    if FLOORS_FILE in files:
        data = git(repo, ["cat-file", "blob", f"{sha}:{FLOORS_FILE}"])
        return parse_floors(data, f"{FLOORS_FILE} at {ref}"), \
            f"base floors: {FLOORS_FILE} at {ref}"
    literals, problems = {}, []
    for path in sorted(p for p in files if Path(p).name == BUILD_FILE):
        text = git(repo, ["cat-file", "blob", f"{sha}:{path}"]).decode("utf-8", "replace")
        values = MIN_BOUND_RE.findall(text)
        if not values:
            continue
        key = module_key(path)
        if len(values) > 1:
            problems.append(f"{path} at {ref} has {len(values)} minBound literals; "
                            "cannot tell which one is the floor")
        elif key is None or key in literals:
            problems.append(f"{path} at {ref}: no unique module key for its minBound literal")
        else:
            literals[key] = int(values[0])
    if problems:
        raise Violation(problems)
    if not literals:
        raise Violation([f"the base {ref} has neither {FLOORS_FILE} nor a minBound(<n>) literal "
                         f"in a {BUILD_FILE}: nothing to compare the floors with"])
    return literals, (f"base floors: minBound literals in the {BUILD_FILE} files at {ref} "
                      f"(the base has no {FLOORS_FILE})")


def check(repo, ref):
    """Returns the report lines, or raises Violation or GitError."""
    sha = resolve(repo, ref)
    base, source = base_floors(repo, ref, sha)
    floors_path = Path(repo) / FLOORS_FILE
    if not floors_path.is_file():
        raise Violation([f"{FLOORS_FILE} is missing in the working tree"])
    floors = parse_floors(floors_path.read_bytes(), FLOORS_FILE)
    modules = working_tree_modules(repo)

    problems, report = [], [source]
    for key in sorted(set(modules) - set(floors)):
        problems.append(f"{modules[key]} reads {FLOORS_FILE}, which has no entry `{key}`")
    for key in sorted(set(floors) - set(modules)):
        problems.append(f"entry `{key}` in {FLOORS_FILE} has no module "
                        f"(no {key}/{BUILD_FILE} reads the file)")
    for key in sorted(set(base) | set(floors)):
        old, new = base.get(key), floors.get(key)
        if old is None:
            report.append(f"  {key}: new, {new}")
        elif new is None:
            report.append(f"  {key}: {old} on the base, gone with its module")
        elif new < old:
            problems.append(f"{key}: floor lowered from {old} (base) to {new} (new)")
        else:
            report.append(f"  {key}: {old} -> {new} ({'equal' if new == old else 'raised'})")
    if problems:
        raise Violation(problems)
    report.append(f"kover floors: ok ({len(floors)} modules, none lower than on the base)")
    return report


# --- self-test ------------------------------------------------------------------------------

FIXTURES = "check-kover-floors-fixtures"


def fixture_path(rel):
    """Fixture trees spell `build.gradle.kts` as `build.gradle.kts.fixture`, so neither Gradle,
    CODEOWNERS nor this script's real run takes them for module build files."""
    parts = list(rel.parts)
    if parts[-1] == BUILD_FILE + ".fixture":
        parts[-1] = BUILD_FILE
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
    """`base/` (committed) and `head/` (the working tree after that commit, uncommitted) trees,
    each optional, and `expect`: `exit: N`, any number of `stdout: <text>` and `stderr: <text>`
    lines that the output must contain and `absent: <text>` lines that neither may contain,
    optional `args: ...` (BASE is the base commit; default `--base BASE`), optional
    `setup: no-repo` (the --repo directory is not a git repository)."""
    expect = {"exit": None, "stdout": [], "stderr": [], "absent": [], "args": None, "setup": None}
    for line in (fixture / "expect").read_text(encoding="utf-8").splitlines():
        key, _, value = line.partition(": ")
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
    if expect["setup"] not in (None, "no-repo"):
        raise ValueError(f"{fixture.name}/expect: unknown setup '{expect['setup']}'")
    with tempfile.TemporaryDirectory(prefix="tm-kover-floors-") as tmp:
        repo = Path(tmp)
        sha = ""
        if expect["setup"] is None:
            self_git(repo, "init", "-q")
            write_tree(repo, fixture / "base")
            self_git(repo, "add", "-A")
            self_git(repo, "commit", "-q", "--allow-empty", "-m", "base")
            sha = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], check=True,
                                 capture_output=True, text=True).stdout.strip()
            write_tree(repo, fixture / "head")
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


def self_test(script_dir):
    failed = total = 0
    fixtures = script_dir / FIXTURES
    entry = script_dir / "check-kover-floors.sh"
    print(f"--- fixtures ({FIXTURES}/, scripts/check-kover-floors.sh in a temporary git repo)")
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
    print(f"check-kover-floors self-test: {total - failed}/{total} cases passed")
    return 1 if failed else 0


def main(argv):
    script_dir = Path(__file__).resolve().parent
    if argv == ["--self-test"]:
        return self_test(script_dir)
    repo, ref, args = Path.cwd(), None, list(argv)
    while args:
        option = args.pop(0)
        if option in ("--repo", "--base") and args and args[0] and not args[0].startswith("-"):
            value = args.pop(0)
            if option == "--repo":
                repo = Path(value)
            else:
                ref = value
        else:
            ref = None
            break
    if ref is None or args:
        print(f"{USAGE} (got {' '.join(argv) or 'no arguments'})", file=sys.stderr)
        return 2
    try:
        report = check(repo, ref)
    except GitError as error:
        print(f"check-kover-floors: {error}", file=sys.stderr)
        return 2
    except Violation as violation:
        for problem in violation.problems:
            print(f"check-kover-floors: {problem}", file=sys.stderr)
        print(f"kover floors: FAILED ({len(violation.problems)} problem"
              f"{'' if len(violation.problems) == 1 else 's'}; a floor can only go up)",
              file=sys.stderr)
        return 1
    print("\n".join(report))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
