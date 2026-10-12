#!/usr/bin/env python3
"""Room schema check and schema export freshness (docs/epics/protected-paths-review-2.md, Decision 4).

Run through scripts/check-room-schema.sh (the entry point). Standard library only.

  check-room-schema.sh [--repo <dir>] --base <ref> [--head <ref>]
  check-room-schema.sh [--repo <dir>] --check-export-fresh
  check-room-schema.sh --self-test

(Not implemented yet: only the self-test and its fixtures exist.)
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

USAGE = ("usage: check-room-schema.sh [--repo <dir>] --base <ref> [--head <ref>] "
         "| [--repo <dir>] --check-export-fresh | --self-test")


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


def self_test(script_dir):
    failed = total = 0
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
    return 0  # stub: the check is not implemented yet


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
