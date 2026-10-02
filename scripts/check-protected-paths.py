#!/usr/bin/env python3
"""Classifies a diff as protected or unprotected, using .github/CODEOWNERS.

Run through scripts/check-protected-paths.sh (the entry point). Standard library only, so it
runs on the stock python3 of macOS and ubuntu-latest without installing anything.

  check-protected-paths.sh [--base <ref>]   classify `git diff --no-renames <ref>...HEAD`
                                            (default ref: origin/main; committed changes only)
  check-protected-paths.sh --files <path>…  classify the given paths instead of reading git
  check-protected-paths.sh --validate       check .github/CODEOWNERS (exit 0 OK, 1 problems)
  check-protected-paths.sh --self-test      run the table-driven and end-to-end cases below
  --root <dir>                              use another tree (used by the self-test)

Classification output, parsed by other tools, so keep it stable: the first line is
`protected` or `unprotected`, then one line per protected file as `<file>  (<pattern>)`,
nothing else. Exit 0 in both cases, exit 2 with a message on stderr for errors (no
CODEOWNERS, unsupported syntax in it, a git failure). The diff uses --no-renames so a file
renamed out of a protected path still shows its old, protected path.

Supported CODEOWNERS subset (what GitHub does for these is the same; anything else is
rejected rather than guessed):
  - `# ...` lines are comments; blank lines are ignored. Each other line is
    `<pattern> <owner>...`.
  - A leading `/` anchors the pattern to the repo root. A pattern with a `/` anywhere but at
    the end is anchored too. A pattern with no `/` (or only a trailing one) matches a name at
    any depth.
  - A trailing `/` matches a directory and everything below it. Without it, a pattern that
    names a directory still matches everything below it.
  - `*` matches any characters except `/`; `?` matches one character except `/`.
  - `**` crosses directories. It must be a whole path segment: `**/x`, `a/**/x`, `a/**`.
  - Matching is case-sensitive.
  - Not supported: negation (`!`), escaped characters (`\\`), character classes (`[...]`).
Every owner must be @ali-roozbahani, so a file is protected when any pattern matches it. The
line reported for a file is its last matching pattern (the one GitHub would use).
"""

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

CODEOWNERS = Path(".github") / "CODEOWNERS"
OWNER = "@ali-roozbahani"
DEFAULT_BASE = "origin/main"
USAGE = ("usage: check-protected-paths.sh [--base <ref> | --files <path>... | --validate | "
         "--self-test] [--root <dir>]")


class Rule:
    def __init__(self, pattern, owners, line):
        self.pattern = pattern
        self.owners = owners
        self.line = line
        self.regex = None
        self.syntax_problem = syntax_problem(pattern)


def syntax_problem(pattern):
    """Returns why the pattern is outside the supported subset, or None."""
    if pattern.startswith("!"):
        return "negation ('!') is not supported"
    if "\\" in pattern:
        return "escaped characters ('\\') are not supported"
    if "[" in pattern or "]" in pattern:
        return "character classes ('[...]') are not supported"
    for segment in pattern.strip("/").split("/"):
        if "**" in segment and segment != "**":
            return "'**' must be a whole path segment ('**/x', 'a/**/x', 'a/**')"
    return None


def compile_pattern(pattern):
    """Translates a supported pattern into a regex that matches whole file paths."""
    dir_only = pattern.endswith("/")
    body = pattern.rstrip("/")
    anchored = body.startswith("/") or "/" in body
    body = body.lstrip("/")

    out = []
    i = 0
    while i < len(body):
        if body.startswith("**/", i):
            out.append("(?:.*/)?")  # zero or more directories
            i += 3
        elif body.startswith("**", i):
            out.append(".*")  # trailing `/**`: everything below
            i += 2
        elif body[i] == "*":
            out.append("[^/]*")
            i += 1
        elif body[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(body[i]))
            i += 1

    prefix = "" if anchored else "(?:.*/)?"
    # Files only are classified, so a directory pattern matches when something is below it.
    suffix = "/.*" if dir_only else "(?:/.*)?"
    return re.compile("^" + prefix + "".join(out) + suffix + "$")


def parse_codeowners(text, where):
    """Returns (rules, problems); a problem is one readable line."""
    rules, problems, seen = [], [], {}
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        rule = Rule(parts[0], parts[1:], number)
        loc = f"{where}:{number}: '{rule.pattern}'"
        if rule.syntax_problem:
            problems.append(f"{loc}: {rule.syntax_problem}")
        else:
            rule.regex = compile_pattern(rule.pattern)
        if not rule.owners:
            problems.append(f"{loc}: no owner (expected {OWNER})")
        for owner in rule.owners:
            if owner != OWNER:
                problems.append(f"{loc}: owner '{owner}' is not {OWNER}")
        if rule.pattern in seen:
            problems.append(f"{loc}: duplicate pattern (also on line {seen[rule.pattern]})")
        else:
            seen[rule.pattern] = number
        rules.append(rule)
    return rules, problems


def matching_rule(rules, path):
    match = None
    for rule in rules:
        if rule.regex is not None and rule.regex.match(path):
            match = rule
    return match


def classify(rules, files):
    """Returns the output lines for a list of repo-relative paths."""
    hits = []
    for path in files:
        rule = matching_rule(rules, path)
        if rule is not None:
            hits.append(f"{path}  ({rule.pattern})")
    return ["protected" if hits else "unprotected"] + hits


def git_lines(root, args):
    result = subprocess.run(["git", "-C", str(root)] + args + ["-z"], capture_output=True)
    if result.returncode != 0:
        message = result.stderr.decode("utf-8", "replace").strip()
        raise RuntimeError(f"git {' '.join(args)} failed: {message}")
    return [p for p in result.stdout.decode("utf-8").split("\0") if p]


def load_rules(root):
    path = root / CODEOWNERS
    if not path.is_file():
        raise RuntimeError(f"{path} not found")
    return parse_codeowners(path.read_text(encoding="utf-8"), str(CODEOWNERS))


def run_classify(root, base, files):
    try:
        rules, _ = load_rules(root)
        unsupported = [f"{CODEOWNERS}:{r.line}: '{r.pattern}': {r.syntax_problem}"
                       for r in rules if r.syntax_problem]
        if unsupported:
            # Fail closed: a pattern this script can't read could hide a protected path.
            raise RuntimeError("unsupported CODEOWNERS syntax, run --validate:\n  "
                               + "\n  ".join(unsupported))
        if files is None:
            files = git_lines(root, ["diff", "--name-only", "--no-renames", f"{base}...HEAD"])
        else:
            files = [f[2:] if f.startswith("./") else f for f in files]
    except RuntimeError as error:
        print(f"check-protected-paths: {error}", file=sys.stderr)
        return 2
    print("\n".join(classify(rules, files)))
    return 0


def run_validate(root):
    try:
        rules, problems = load_rules(root)
        tracked = git_lines(root, ["ls-files"])
    except RuntimeError as error:
        print(f"check-protected-paths: {error}", file=sys.stderr)
        return 2
    for rule in rules:
        if rule.regex is not None and not any(rule.regex.match(p) for p in tracked):
            problems.append(f"{CODEOWNERS}:{rule.line}: '{rule.pattern}': matches no tracked file")
    problems.sort(key=lambda p: int(p.split(":")[1]))
    for problem in problems:
        print(problem)
    if problems:
        print(f"check-protected-paths: FAILED, {len(problems)} problem(s) in {CODEOWNERS}")
        return 1
    print(f"check-protected-paths: OK, {len(rules)} patterns in {CODEOWNERS}")
    return 0


# --- self-test ------------------------------------------------------------------------------

# (pattern, path, expected match), one group per syntax rule in the module docstring.
MATCH_CASES = [
    # A leading `/` anchors to the repo root; matching is case-sensitive.
    ("/CLAUDE.md", "CLAUDE.md", True),
    ("/CLAUDE.md", "docs/CLAUDE.md", False),
    ("/CLAUDE.md", "claude.md", False),
    ("/CLAUDE.md", "CLAUDE.md.bak", False),
    # A `/` in the middle anchors too.
    ("docs/epics/", "docs/epics/plan.md", True),
    ("docs/epics/", "app/docs/epics/plan.md", False),
    # No `/`: a name at any depth.
    ("build.gradle.kts", "build.gradle.kts", True),
    ("build.gradle.kts", "data/build.gradle.kts", True),
    ("build.gradle.kts", "androidApp/app/build.gradle.kts", True),
    ("build.gradle.kts", "settings.gradle.kts", False),
    ("build.gradle.kts", "build.gradle.kts.orig", False),
    ("build.gradle.kts", "buildXgradle.kts", False),  # `.` is literal
    # Only a trailing `/`: a directory name at any depth.
    ("schemas/", "data/schemas/v1.json", True),
    ("schemas/", "schemas/v1.json", True),
    ("schemas/", "data/schemas", False),  # a file named like the directory
    # A trailing `/` matches a directory and everything below it.
    ("/gradle/", "gradle/libs.versions.toml", True),
    ("/gradle/", "gradle/wrapper/gradle-wrapper.jar", True),
    ("/gradle/", "gradle.properties", False),
    ("/gradle/", "gradle", False),
    ("/gradle/", "data/gradle/x", False),
    # Without a trailing `/`, a directory still matches everything below it.
    ("/shared", "shared/build.gradle.kts", True),
    ("/shared", "shared", True),
    ("/shared", "sharedkit/x.kt", False),
    # `*` does not cross `/`.
    ("/scripts/*.sh", "scripts/check-board.sh", True),
    ("/scripts/*.sh", "scripts/claude-hooks/block-git-push.sh", False),
    ("/data/src/*Main/db/", "data/src/commonMain/db/A.kt", True),
    ("/data/src/*Main/db/", "data/src/iosMain/db/A.kt", True),
    ("/data/src/*Main/db/", "data/src/commonTest/db/A.kt", False),
    ("/data/src/*Main/db/", "data/src/x/commonMain/db/A.kt", False),
    # `?` is one character, not `/`.
    ("/a?.txt", "ab.txt", True),
    ("/a?.txt", "abc.txt", False),
    ("/a?.txt", "a/.txt", False),
    # `**` crosses directories.
    ("**/Package.swift", "Package.swift", True),
    ("**/Package.swift", "iosApp/Packages/Route/Package.swift", True),
    ("/docs/**/plan.md", "docs/plan.md", True),
    ("/docs/**/plan.md", "docs/a/b/plan.md", True),
    ("/docs/**/plan.md", "docs/a/b/other.md", False),
    ("/docs/**", "docs/a/b/c.md", True),
    ("/docs/**", "docsx/a.md", False),
]

SYNTAX_CASES = [
    ("!/docs/", "negation"),
    ("/a\\ b", "escaped characters"),
    ("/src/[ab].kt", "character classes"),
    ("/docs/a**", "whole path segment"),
]

GOOD_CODEOWNERS = """# test fixture
/.github/          @ali-roozbahani
/CLAUDE.md         @ali-roozbahani
build.gradle.kts   @ali-roozbahani
/docs/epics/       @ali-roozbahani
"""

TRACKED = [".github/CODEOWNERS", "CLAUDE.md", "build.gradle.kts", "data/build.gradle.kts",
           "docs/epics/plan.md", "README.md", "data/src/A.kt"]

# (name, CODEOWNERS text or None for GOOD_CODEOWNERS, args, exit code, exact stdout or None,
#  texts that must appear in stdout + stderr)
E2E_CASES = [
    ("files: protected only", None, ["--files", "CLAUDE.md", "data/build.gradle.kts"], 0,
     "protected\nCLAUDE.md  (/CLAUDE.md)\ndata/build.gradle.kts  (build.gradle.kts)\n", []),
    ("files: unprotected only", None, ["--files", "README.md", "./data/src/A.kt"], 0,
     "unprotected\n", []),
    ("files: mixed", None, ["--files", "README.md", "docs/epics/new.md", "data/src/A.kt"], 0,
     "protected\ndocs/epics/new.md  (/docs/epics/)\n", []),
    ("files: none", None, ["--files"], 0, "unprotected\n", []),
    ("diff: unprotected branch", None, ["--base", "main"], 0, "unprotected\n", []),
    ("diff: mixed branch", None, ["--base", "main", "--branch", "mixed"], 0,
     "protected\nCLAUDE.md  (/CLAUDE.md)\n", []),
    ("diff: renamed out of a protected path", None, ["--base", "main", "--branch", "rename"], 0,
     "protected\ndocs/epics/plan.md  (/docs/epics/)\n", []),
    ("diff: bad base ref", None, ["--base", "no-such-ref"], 2, "", ["git diff", "failed"]),
    ("classify: unsupported syntax is an error", "!/CLAUDE.md @ali-roozbahani\n",
     ["--files", "CLAUDE.md"], 2, "", ["unsupported CODEOWNERS syntax", "negation"]),
    ("validate: OK", None, ["--validate"], 0, None, ["OK, 4 patterns"]),
    ("validate: negation", GOOD_CODEOWNERS + "!/CLAUDE.md @ali-roozbahani\n", ["--validate"], 1,
     None, ["CODEOWNERS:6: '!/CLAUDE.md': negation ('!') is not supported"]),
    ("validate: escaped character", GOOD_CODEOWNERS + "/README\\.md @ali-roozbahani\n",
     ["--validate"], 1, None, ["CODEOWNERS:6: '/README\\.md': escaped characters"]),
    ("validate: character class", GOOD_CODEOWNERS + "/[R]EADME.md @ali-roozbahani\n",
     ["--validate"], 1, None, ["CODEOWNERS:6: '/[R]EADME.md': character classes"]),
    ("validate: '**' inside a segment", GOOD_CODEOWNERS + "/data/src** @ali-roozbahani\n",
     ["--validate"], 1, None, ["CODEOWNERS:6: '/data/src**': '**' must be a whole path segment"]),
    ("validate: other owner", GOOD_CODEOWNERS + "/README.md @someone-else\n", ["--validate"], 1,
     None, ["CODEOWNERS:6: '/README.md': owner '@someone-else' is not @ali-roozbahani"]),
    ("validate: no owner", GOOD_CODEOWNERS + "/README.md\n", ["--validate"], 1,
     None, ["CODEOWNERS:6: '/README.md': no owner"]),
    ("validate: duplicate pattern", GOOD_CODEOWNERS + "/CLAUDE.md @ali-roozbahani\n",
     ["--validate"], 1, None, ["CODEOWNERS:6: '/CLAUDE.md': duplicate pattern (also on line 3)"]),
    ("validate: matches no tracked file", GOOD_CODEOWNERS + "/missing/ @ali-roozbahani\n",
     ["--validate"], 1, None, ["CODEOWNERS:6: '/missing/': matches no tracked file",
                               "FAILED, 1 problem(s)"]),
    ("missing CODEOWNERS", "", ["--files", "CLAUDE.md"], 2, "", ["CODEOWNERS not found"]),
]


def git(repo, *args):
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=self-test",
                    "-c", "user.email=self-test@example.invalid", "-c", "commit.gpgsign=false"]
                   + list(args), check=True, capture_output=True)


def make_repo(repo, codeowners):
    """main holds TRACKED; branch `unprotected` edits README.md, `mixed` edits README.md and
    CLAUDE.md, `rename` moves docs/epics/plan.md to notes/plan.md."""
    git(repo, "init", "-q")
    git(repo, "checkout", "-q", "-b", "main")
    for name in TRACKED:
        (repo / name).parent.mkdir(parents=True, exist_ok=True)
        (repo / name).write_text(f"{name}\n", encoding="utf-8")
    if codeowners:
        (repo / CODEOWNERS).parent.mkdir(exist_ok=True)
        (repo / CODEOWNERS).write_text(codeowners, encoding="utf-8")
    else:
        (repo / CODEOWNERS).unlink()  # TRACKED created it as a placeholder
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "base")
    for branch, edits in [("mixed", ["README.md", "CLAUDE.md"]), ("unprotected", ["README.md"])]:
        git(repo, "checkout", "-q", "-b", branch, "main")
        for name in edits:
            (repo / name).write_text("changed\n", encoding="utf-8")
        git(repo, "commit", "-q", "-am", branch)
    git(repo, "checkout", "-q", "-b", "rename", "main")
    (repo / "notes").mkdir()
    git(repo, "mv", "docs/epics/plan.md", "notes/plan.md")
    git(repo, "commit", "-q", "-m", "rename")
    git(repo, "checkout", "-q", "unprotected")


def self_test(script_dir):
    failed = total = 0

    print("--- matcher")
    for pattern, path, expected in MATCH_CASES:
        total += 1
        actual = bool(compile_pattern(pattern).match(path))
        status = "ok  " if actual == expected else "FAIL"
        failed += actual != expected
        print(f"    {status} {pattern!r:24} {path!r:44} expected {expected}, got {actual}")
    for pattern, expected in SYNTAX_CASES:
        total += 1
        problem = syntax_problem(pattern) or ""
        ok = expected in problem
        failed += not ok
        print(f"    {'ok  ' if ok else 'FAIL'} {pattern!r:24} rejected: {problem or 'NOT REJECTED'}")

    print("--- end to end (scripts/check-protected-paths.sh in a temporary git repo)")
    entry = script_dir / "check-protected-paths.sh"
    for name, codeowners, args, exit_code, stdout, contains in E2E_CASES:
        total += 1
        args = list(args)
        branch = "unprotected"
        if "--branch" in args:
            index = args.index("--branch")
            branch = args[index + 1]
            del args[index:index + 2]
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            make_repo(repo, GOOD_CODEOWNERS if codeowners is None else codeowners)
            git(repo, "checkout", "-q", branch)
            env = dict(os.environ, LC_ALL="C")
            result = subprocess.run(["bash", str(entry), "--root", str(repo)] + args,
                                    capture_output=True, text=True, env=env)
        output = result.stdout + result.stderr
        errors = []
        if result.returncode != exit_code:
            errors.append(f"exit {result.returncode}, expected {exit_code}")
        if stdout is not None and result.stdout != stdout:
            errors.append(f"stdout {result.stdout!r}, expected {stdout!r}")
        errors += [f"missing: {c}" for c in contains if c not in output]
        failed += bool(errors)
        print(f"    {'FAIL' if errors else 'ok  '} {name}: exit {result.returncode}")
        print("".join(f"         | {line}\n" for line in output.splitlines()), end="")
        print("".join(f"         SELF-TEST FAIL: {e}\n" for e in errors), end="")

    print(f"check-protected-paths self-test: {total - failed}/{total} cases passed")
    return 1 if failed else 0


def main(argv):
    script_dir = Path(__file__).resolve().parent
    root = script_dir.parent
    mode, base, files = "classify", DEFAULT_BASE, None
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--base" and args and mode == "classify" and files is None:
            base = args.pop(0)
        elif arg == "--files" and mode == "classify" and base == DEFAULT_BASE:
            files = []
            while args and not args[0].startswith("--"):
                files.append(args.pop(0))
        elif arg == "--validate" and mode == "classify":
            mode = "validate"
        elif arg == "--self-test" and mode == "classify":
            mode = "self-test"
        elif arg == "--root" and args:
            root = Path(args.pop(0)).resolve()
        else:
            print(f"{USAGE} (got '{arg}')", file=sys.stderr)
            return 2
    if mode != "classify" and (base != DEFAULT_BASE or files is not None):
        print(f"{USAGE} (--base and --files only classify)", file=sys.stderr)
        return 2
    if mode == "self-test":
        return self_test(script_dir)
    if mode == "validate":
        return run_validate(root)
    return run_classify(root, base, files)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
