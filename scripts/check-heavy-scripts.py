#!/usr/bin/env python3
"""check-heavy-scripts: the list of scripts that stay full (HEAVY_SCRIPTS in classify-changes.sh)
must contain every script that the Android or iOS build or tests run.

A pull request that changes only tooling scripts is classified light (scripts/classify-changes.sh):
CI's Android and iOS jobs skip their heavy steps. That is only right for a script no heavy step runs.
This check reads what the heavy steps run and fails for a script that the classifier would call light:

  * the Xcode project (build phases, scheme pre-actions): iosApp/TrailMetrics.xcodeproj
  * Gradle: *.gradle.kts, *.gradle, gradle.properties, buildSrc/, gradle/ (comment lines left out)
  * CI: the steps of .github/workflows/ci.yml that are skipped when the decision is light
    (`if: ... decision != 'light'` on the step, or on its job)
  * the gate: the top-level `if [ "$DECISION" ...` and `if [ "$RUN_IOS_STEPS" ...` blocks of
    scripts/pre-push-check.sh
  * scripts/checks/self-tests.list: the scripts of the groups that only the heavy CI steps run; the
    groups come from the `self-tests.sh --run <groups>` arguments in ci.yml, and a group no CI step runs
    is a problem of its own
  * what those scripts start themselves: every script a referenced heavy script names outside its
    comment lines, and so on (the control scripts classify-changes.sh, ci/, checks/ and
    pre-push-check.sh are not followed: they name the always-run checks too)

A reference counts when it is `scripts/<path>` and the path exists. The classifier is the oracle
(`classify-changes.sh --files <path>`), so this check has no copy of the list.

Usage: check-heavy-scripts.py [--root <dir>]
A source that exists but cannot be read is an error (exit 2), never a pass.

Exit 0 ok (or nothing to check), 1 a script is missing from the list (report on stdout), 2 error.
"""
import os
import re
import subprocess
import sys

REF = re.compile(r"scripts/[A-Za-z0-9_][A-Za-z0-9_./-]*")
LIGHT_IF = re.compile(r"decision\s*!=\s*'light'")
GATE_BLOCK_START = re.compile(r'^if \[ "\$(DECISION|RUN_IOS_STEPS)" ')
# Control scripts: heavy for their own reasons (see HEAVY_SCRIPTS); not followed.
NOT_FOLLOWED = ("scripts/classify-changes.sh", "scripts/pre-push-check.sh", "scripts/ci/", "scripts/checks/",
                "scripts/check-heavy-scripts.")
RUN_GROUPS = re.compile(r"self-tests\.sh\s+--run\s+([A-Za-z0-9_ -]+)")


class Unreadable(Exception):
    pass


def read(path):
    """The text of the file, None when it does not exist; a file that exists and cannot be read raises."""
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError as error:
        raise Unreadable("%s exists but cannot be read: %s" % (path, error.strerror or error))


def walk_error(error):
    raise Unreadable("cannot read %s: %s" % (error.filename, error.strerror or error))


def code_lines(text):
    """The lines that are not whole-line comments (`#`, `//`)."""
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("#") or stripped.startswith("//"):
            continue
        yield line


def refs_in(lines):
    found = []
    for line in lines:
        for match in REF.findall(line):
            found.append(match.rstrip("./-") if not match.endswith((".sh", ".py")) else match)
    return found


class Checker:
    def __init__(self, root):
        self.root = root
        self.classifier = os.path.join(os.path.dirname(os.path.abspath(__file__)), "classify-changes.sh")
        self.cache = {}
        self.problems = []
        self.checked = 0
        self.sources = 0

    def exists(self, rel):
        return os.path.exists(os.path.join(self.root, rel))

    def is_heavy(self, rel):
        if rel not in self.cache:
            probe = rel + "/_" if os.path.isdir(os.path.join(self.root, rel)) else rel
            try:
                out = subprocess.run(["bash", self.classifier, "--files", probe], capture_output=True, text=True, check=False)
            except OSError as error:
                print("check-heavy-scripts: cannot run the classifier: %s" % error, file=sys.stderr)
                sys.exit(2)
            if out.returncode != 0:
                print("check-heavy-scripts: the classifier failed for %s: %s" % (rel, out.stderr.strip()), file=sys.stderr)
                sys.exit(2)
            self.cache[rel] = out.stdout.splitlines()[:1] == ["full"]
        return self.cache[rel]

    def require(self, rel, started_by, work):
        """rel is started by a heavy step: it must classify full. Returns True when it was checked."""
        if not self.exists(rel):
            return False
        self.checked += 1
        if not self.is_heavy(rel):
            self.problems.append("%s is started by %s but classify-changes.sh would call it light: add it to HEAVY_SCRIPTS" % (rel, started_by))
        else:
            work.append((rel, started_by))
        return True

    def run(self):
        work = []
        seen = set()

        def feed(refs, started_by):
            for rel in refs:
                key = (rel, started_by)
                if key in seen:
                    continue
                seen.add(key)
                self.require(rel, started_by, work)

        # Xcode project.
        xcode = os.path.join(self.root, "iosApp", "TrailMetrics.xcodeproj")
        for base, _dirs, files in (os.walk(xcode, onerror=walk_error) if os.path.isdir(xcode) else []):
            for name in sorted(files):
                path = os.path.join(base, name)
                text = read(path)
                if text is None:
                    continue
                self.sources += 1
                feed(refs_in(text.splitlines()), os.path.relpath(path, self.root))
        # Gradle.
        for base, dirs, files in os.walk(self.root, onerror=walk_error):
            dirs[:] = [d for d in dirs if d not in (".git", "build", ".gradle", ".kotlin", ".build", "node_modules", "scripts", "docs", ".claude", "iosApp")]
            rel_base = os.path.relpath(base, self.root)
            for name in sorted(files):
                rel = os.path.normpath(os.path.join(rel_base, name))
                top = rel.split(os.sep)[0]
                if not (name.endswith(".gradle.kts") or name.endswith(".gradle") or name == "gradle.properties"
                        or top in ("buildSrc", "gradle")):
                    continue
                if name.endswith((".jar", ".bin")):
                    continue
                text = read(os.path.join(self.root, rel))
                if text is None:
                    continue
                self.sources += 1
                feed(refs_in(code_lines(text)), rel)
        # CI steps that a light decision skips.
        ci = read(os.path.join(self.root, ".github", "workflows", "ci.yml"))
        groups_heavy, groups_light = set(), set()
        if ci is not None:
            self.sources += 1
            for step_name, text, heavy in self.ci_steps(ci):
                for found in RUN_GROUPS.findall("\n".join(code_lines(text))):
                    (groups_heavy if heavy else groups_light).update(found.split())
                if heavy:
                    feed(refs_in(code_lines(text)), ".github/workflows/ci.yml, step '%s'" % step_name)
        # The gate's heavy blocks.
        gate = read(os.path.join(self.root, "scripts", "pre-push-check.sh"))
        if gate is not None:
            self.sources += 1
            feed(refs_in(code_lines("\n".join(self.gate_blocks(gate)))), "scripts/pre-push-check.sh (its DECISION and RUN_IOS_STEPS blocks)")
        # The self-tests that only the iOS job runs.
        lst = read(os.path.join(self.root, "scripts", "checks", "self-tests.list"))
        if lst is not None:
            self.sources += 1
            for line in lst.splitlines():
                parts = line.split("\t")
                if len(parts) != 3 or line.startswith("#"):
                    continue
                group = parts[0]
                if group in groups_light:
                    continue
                if group in groups_heavy:
                    feed([parts[2]], "scripts/checks/self-tests.list (group %s, run only by CI steps that a light decision skips)" % group)
                elif ci is None:
                    self.problems.append("scripts/checks/self-tests.list has group '%s' but there is no .github/workflows/ci.yml to say which step runs it" % group)
                else:
                    self.problems.append("scripts/checks/self-tests.list group '%s' (%s) is run by no step of ci.yml: say where it runs, so that the scripts of a heavy-only group can be kept on the list of heavy scripts" % (group, parts[2]))
        # What the heavy scripts start themselves.
        while work:
            rel, _started_by = work.pop()
            if rel.startswith(NOT_FOLLOWED) or not rel.endswith((".sh", ".py")):
                continue
            text = read(os.path.join(self.root, rel))
            if text is None:
                continue
            feed([r for r in refs_in(code_lines(text)) if r != rel], rel)
        return self.problems

    @staticmethod
    def ci_steps(text):
        """(name, text, heavy) of each step, heavy when a light decision skips it, in ci.yml's own layout:
        jobs at 2 spaces under `jobs:`, a job's `if:` at 4, steps as `      - ` items, a step's `if:` at 8."""
        lines = text.splitlines()
        steps = []
        in_jobs = False
        job_heavy = False
        current = None

        def close():
            nonlocal current
            if current is not None:
                name, body, heavy = current
                steps.append((name, "\n".join(body), job_heavy or heavy))
            current = None

        for line in lines:
            if re.match(r"^jobs:\s*$", line):
                in_jobs = True
                continue
            if not in_jobs:
                continue
            if re.match(r"^  [A-Za-z0-9_-]+:\s*$", line):
                close()
                job_heavy = False
                continue
            if re.match(r"^    if:", line) and LIGHT_IF.search(line):
                job_heavy = True
                continue
            if re.match(r"^      - ", line):
                close()
                name = re.sub(r"^      - (name:\s*)?", "", line).strip() or "(unnamed)"
                current = [name, [line], bool(re.match(r"^      - if:", line) and LIGHT_IF.search(line))]
                continue
            if current is not None:
                current[1].append(line)
                if re.match(r"^        if:", line) and LIGHT_IF.search(line):
                    current[2] = True
                if re.match(r"^        name:", line) and current[0] == "(unnamed)":
                    current[0] = line.split(":", 1)[1].strip()
        close()
        return steps

    @staticmethod
    def gate_blocks(text):
        inside = False
        for line in text.splitlines():
            if not inside and GATE_BLOCK_START.match(line):
                inside = True
            if inside:
                yield line
                if re.match(r"^fi\b", line):
                    inside = False


def main(argv):
    root = None
    args = argv[1:]
    while args:
        if args[0] == "--root" and len(args) >= 2:
            root = args[1]
            args = args[2:]
        else:
            print("usage: check-heavy-scripts.py [--root <dir>]", file=sys.stderr)
            return 2
    if root is None:
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    root = os.path.abspath(root)
    if not os.path.isdir(root):
        print("check-heavy-scripts: %s is not a directory" % root, file=sys.stderr)
        return 2
    checker = Checker(root)
    try:
        problems = checker.run()
    except Unreadable as error:
        print("check-heavy-scripts: %s" % error, file=sys.stderr)
        return 2
    if checker.sources == 0:
        print("check-heavy-scripts: no heavy-step sources under %s: nothing checked" % root)
        return 0
    if problems:
        print("check-heavy-scripts: FAILED, %d problem(s)" % len(problems))
        for problem in problems:
            print(problem)
        return 1
    print("check-heavy-scripts: OK, %d reference(s) from %d source(s) are on the list of heavy scripts" % (checker.checked, checker.sources))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
