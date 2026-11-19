#!/usr/bin/env python3
"""Fails when a workflow under .github/workflows/ has a `push` trigger that can fire on a branch that has pull requests.

Run through scripts/check-ci-triggers.sh (the entry point). Standard library only, so it runs on the stock
python3 of macOS and ubuntu-latest, which has no YAML parser: the `on:` block is read with a small reader of
the shapes below, and a workflow it cannot read is a failure, never a pass.

  check-ci-triggers.sh                    scan every .github/workflows/*.yml and *.yaml of the checkout
  check-ci-triggers.sh --file <path>...   scan these files (the fixtures use it)
  check-ci-triggers.sh --self-test        the fixtures in scripts/check-ci-triggers-fixtures/, then the real workflows

Why: a `push` run and a `pull_request` run for the same head commit are two runs, and their concurrency groups
differ (ci.yml: `ci-<workflow>-<sha>` against `ci-<workflow>-<PR number>`), so nothing dedupes them. A branch that
gets a push trigger and also a pull request is tested twice, and the macOS iOS job makes the second run costly. An
epic integration branch was the case that found it (docs/epics/route-completion-to-domain.md; decisions-history.md
of the epic-orchestration skill).

The rule: the branches of a `push` trigger are only branches that are never the head of a pull request. Today that
is `main` (ALLOWED_PUSH_BRANCHES below), which is tested after a merge.

What it covers, in every workflow file:
  - `push` with `branches:` holding anything but `main` (`feature/epic/**`, `feature/**`, `**`, `chore/x`, ...);
  - `push` with no branch filter, which runs on every branch (a bare `push:`, `on: push`, `on: [push, ...]`);
  - `push` with `branches-ignore:`, which allows every branch it does not name.
What it does not cover: the `pull_request` filters (they match the base branch of a PR, which is a different
question); `pull_request_target`, `workflow_dispatch`, `schedule` and `workflow_run`; a `push` that only has `tags:`
(a tag push is not a branch with pull requests); whether `main` itself ever has a pull request (it does not: a
merge is a push to `main`); the `paths` filters; and the shape of the jobs. A branch name other than `main` is
treated as one that can have a pull request, because the check cannot see which branches do: a branch that
truly never has one is added to ALLOWED_PUSH_BRANCHES in a PR the owner reviews.

Exit 0 clean, 1 a hit (listed as `<file>: <reason>`), 2 a file that cannot be read or has no `on:` (fail closed).
"""
import glob
import os
import re
import subprocess
import sys

ALLOWED_PUSH_BRANCHES = {"main"}
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FIXTURES = os.path.join(HERE, "check-ci-triggers-fixtures")


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


def significant(lines):
    """(index, line) of every line that is not blank or a comment."""
    for i, line in enumerate(lines):
        s = line.strip()
        if s and not s.startswith("#"):
            yield i, line.rstrip("\n")


def strip_quotes(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        return value[1:-1]
    return value


def flow_list(text):
    """`[ a, 'b' ]` -> ['a', 'b'] (a trailing comment is cut off first); None when it is not a flow list."""
    text = re.sub(r"\s+#.*$", "", text.strip())
    if not (text.startswith("[") and text.endswith("]")):
        return None
    inner = text[1:-1].strip()
    return [strip_quotes(p) for p in inner.split(",") if p.strip()]


def key_value(line):
    m = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_-]*|\"[^\"]+\"|'[^']+')\s*:\s*(.*)$", line)
    if not m:
        return None
    return strip_quotes(m.group(1)), m.group(2).strip()


def on_block(lines):
    """The `on:` entry of a workflow: ('inline', value) or ('block', [lines of the block]); None when there is none."""
    for i, line in significant(lines):
        if indent_of(line) != 0:
            continue
        kv = key_value(line)
        if kv and kv[0] == "on":
            value = re.sub(r"\s+#.*$", "", kv[1])
            if value:
                return "inline", value
            block = []
            for j, nxt in significant(lines[i + 1:]):
                if indent_of(nxt) == 0:
                    break
                block.append(nxt)
            return "block", block
    return None


def push_filters(block):
    """From the lines of a block `on:`: None when there is no `push` trigger, else the dict of its filters.
    A bare `push:` is {} (no filter)."""
    if not block:
        return None
    child = indent_of(block[0])
    for i, line in enumerate(block):
        kv = key_value(line)
        if indent_of(line) == child and kv and kv[0] == "push":
            if kv[1] and flow_list(kv[1]) is None and kv[1] not in ("{}", "null", "~"):
                raise ValueError("an unreadable value for push: %r" % kv[1])
            sub = []
            j = i + 1
            while j < len(block) and indent_of(block[j]) > child:
                sub.append(block[j])
                j += 1
            return read_filters(sub)
    return None


def read_filters(sub):
    filters = {}
    if not sub:
        return filters
    base = indent_of(sub[0])
    i = 0
    while i < len(sub):
        line = sub[i]
        kv = key_value(line)
        if indent_of(line) == base and kv:
            name, value = kv
            if value:
                items = flow_list(value)
                if items is None:
                    raise ValueError("an unreadable value for %s: %r" % (name, value))
                filters[name] = items
            else:
                items = []
                j = i + 1
                while j < len(sub) and indent_of(sub[j]) >= base:
                    m = re.match(r"^\s*-\s+(.*?)\s*(#.*)?$", sub[j])
                    if m and indent_of(sub[j]) >= base:
                        items.append(strip_quotes(m.group(1)))
                    j += 1
                filters[name] = items
        i += 1
    return filters


def check_text(path, text):
    """List of problems of one workflow file; raises ValueError when it cannot be read."""
    lines = text.split("\n")
    on = on_block(lines)
    if on is None:
        raise ValueError("no `on:` block")
    kind, value = on
    problems = []
    if kind == "inline":
        names = flow_list(value) or [strip_quotes(value)]
        if "push" in names:
            problems.append("push is a trigger with no branch filter, so it runs on every branch")
        return problems
    filters = push_filters(value)
    if filters is None:
        return problems
    if "branches-ignore" in filters:
        problems.append("push uses branches-ignore, which allows every branch it does not name")
    branches = filters.get("branches")
    if branches is None:
        if "branches-ignore" not in filters and "tags" not in filters:
            problems.append("push has no branch filter, so it runs on every branch")
        return problems
    for b in branches:
        if b not in ALLOWED_PUSH_BRANCHES:
            problems.append("push runs on '%s', a branch that can have a pull request (a push and a pull_request run "
                            "for one commit are two runs); only %s may be pushed-to without one"
                            % (b, ", ".join(sorted(ALLOWED_PUSH_BRANCHES))))
    return problems


def scan(paths):
    code = 0
    for path in paths:
        try:
            with open(path, encoding="utf-8") as f:
                problems = check_text(path, f.read())
        except (OSError, ValueError) as e:
            print("%s: cannot read the triggers: %s (a check that could not look is not a pass)" % (path, e))
            code = 2
            continue
        shown = os.path.relpath(path, ROOT) if path.startswith(ROOT) else path
        for p in problems:
            print("%s: %s" % (shown, p))
        if problems and code != 2:
            code = 1
    return code


def workflows():
    found = sorted(glob.glob(os.path.join(ROOT, ".github", "workflows", "*.yml")) +
                   glob.glob(os.path.join(ROOT, ".github", "workflows", "*.yaml")))
    return found


def self_test():
    cases = [  # fixture, expected exit code
        ("green-main-only.yml", 0),
        ("green-main-block-list.yml", 0),
        ("green-no-push.yml", 0),
        ("green-tags-only.yml", 0),
        ("red-epic-push.yml", 1),
        ("red-epic-push-block-list.yml", 1),
        ("red-feature-glob.yml", 1),
        ("red-all-branches-glob.yml", 1),
        ("red-push-no-filter.yml", 1),
        ("red-inline-push.yml", 1),
        ("red-branches-ignore.yml", 1),
        ("unreadable-no-on.yml", 2),
    ]
    failed = 0
    for name, want in cases:
        path = os.path.join(FIXTURES, name)
        got = subprocess.run([sys.executable, os.path.abspath(__file__), "--file", path],
                             capture_output=True, text=True).returncode
        if got != want:
            print("FAIL %s: exit %d, expected %d" % (name, got, want)); failed += 1
        else:
            print("ok   %s -> exit %d" % (name, got))
    real = workflows()
    if not real:
        print("FAIL no workflow found under .github/workflows/"); failed += 1
    else:
        got = scan(real)
        if got != 0:
            print("FAIL the committed workflows break the rule (above)"); failed += 1
        else:
            print("ok   the committed workflows (%d files) -> clean" % len(real))
    if failed == 0:
        print("check-ci-triggers self-test: all cases passed")
        return 0
    print("check-ci-triggers self-test: %d failed" % failed)
    return 1


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    if argv[:1] == ["--file"] and len(argv) > 1:
        return scan(argv[1:])
    if not argv:
        real = workflows()
        if not real:
            print("check-ci-triggers: no workflow found under .github/workflows/ (not a pass)")
            return 2
        code = scan(real)
        if code == 0:
            print("check-ci-triggers: %d workflow file(s), no push trigger on a branch that can have a pull request" % len(real))
        return code
    print("usage: scripts/check-ci-triggers.sh [--file <path>... | --self-test]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
