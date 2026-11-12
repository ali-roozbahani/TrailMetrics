#!/usr/bin/env python3
"""Checks BOARD.md's record format and prints the record to take next.

Run through scripts/check-board.sh (the entry point). Standard library only, so it runs on
the stock python3 of macOS and ubuntu-latest without installing anything.

  check-board.sh              check BOARD.md and the board mentions in the skills and docs
                              (a gone slug under docs/epics/ only prints a notice)
  check-board.sh --next       print the first record in Order whose After slugs are all gone
  check-board.sh --self-test  run the fixtures in scripts/check-board-fixtures/
  --root <dir>                check another tree (used by the fixtures); default: repo root
  --base <rev>                also fail when the slug of a record that BOARD.md has at <rev> and
                              no longer has is still named in any other file (docs/epics/ only
                              prints a notice). The gate passes the merge-base with origin/main; in
                              a pull_request run of GitHub Actions without --base the base branch is
                              fetched (depth 1), so CI needs no extra flag.
  --base-board <file>         the same with the old BOARD.md read from a file (the fixtures)

The record format is described in BOARD.md's header; the rules in tm-pr-workflow → "Board".
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SECTION_TYPES = {"Epics": "epic", "Tasks": "task", "Drift": "drift"}
FIELDS = ["Type", "Area", "Order", "After", "Source", "Problem", "Done when", "Refs"]
OPTIONAL_FIELDS = {"After"}

SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
FIELD_RE = re.compile(r"^- ([A-Z][A-Za-z]*(?: [a-z]+)?): ?(.*)$")

# Line numbers go stale with every edit, so the board refers to code by symbol only.
# "400-line limit" or "284 lines:" are sizes, not line numbers: the number must follow "line".
LINE_NUMBER_PATTERNS = [
    (re.compile(r"\b[\w./-]+\.[A-Za-z]{1,10}:\d+"), "file:line reference"),
    (re.compile(r"\blines? \d+(?:[-–]\d+)?", re.IGNORECASE), "'line N' reference"),
    (re.compile(r"(?<![\w-])#?L\d+\b"), "'LN' reference"),
]

# board `slug`, board record `slug`, and lists continued with commas: board `a`, `b`.
BOARD_MENTION_RE = re.compile(r"\bboard (?:record )?(`[^`\n]+`(?:,\s*`[^`\n]+`)*)", re.IGNORECASE)
BACKTICKED_RE = re.compile(r"`([^`\n]+)`")

# Epic plans are historical: they stay as written once the epic runs, so a mention of a record
# that is gone is a notice there, not a failure. This one directory is the whole exception;
# a mention in a skill, CLAUDE.md, README.md, another doc or BOARD.md itself still fails.
HISTORICAL_PLAN_DIR = Path("docs") / "epics"


class Record:
    def __init__(self, slug, section, line):
        self.slug = slug
        self.section = section
        self.line = line
        self.fields = []  # (name, value, line)

    def get(self, name):
        for field_name, value, _ in self.fields:
            if field_name == name:
                return value
        return None

    @property
    def order(self):
        value = self.get("Order")
        return int(value) if value is not None and value.strip().isdigit() else None

    @property
    def after(self):
        value = self.get("After")
        if value is None:
            return []
        return [s.strip().strip("`") for s in value.split(",") if s.strip()]


def parse_board(text, problems):
    records = []
    section = None
    record = None
    for number, line in enumerate(text.splitlines(), start=1):
        if line.startswith("## "):
            section = line[3:].strip()
            record = None
            if section not in SECTION_TYPES:
                problems.append(f"BOARD.md:{number}: unknown section '{section}' "
                                f"(expected one of {', '.join(SECTION_TYPES)})")
            continue
        if line.startswith("### "):
            record = Record(line[4:].strip(), section, number)
            records.append(record)
            if section is None:
                problems.append(f"BOARD.md:{number}: record '{record.slug}' is not under a section")
            continue
        if record is None:
            continue
        match = FIELD_RE.match(line)
        if match:
            record.fields.append((match.group(1), match.group(2), number))
        elif line.strip() and record.fields:
            name, value, field_line = record.fields[-1]
            record.fields[-1] = (name, value + " " + line.strip(), field_line)
        elif line.strip():
            problems.append(f"BOARD.md:{number}: '{record.slug}': text before the first field")
    return records


def check_fields(records, problems):
    seen = {}
    for r in records:
        where = f"BOARD.md:{r.line}: '{r.slug}'"
        if not SLUG_RE.match(r.slug):
            problems.append(f"{where}: slug is not kebab-case")
        if r.slug in seen:
            problems.append(f"{where}: duplicate slug (also at BOARD.md:{seen[r.slug]})")
        else:
            seen[r.slug] = r.line

        names = [name for name, _, _ in r.fields]
        for name in names:
            if name not in FIELDS:
                problems.append(f"{where}: unknown field '{name}'")
            elif names.count(name) > 1:
                problems.append(f"{where}: field '{name}' appears {names.count(name)} times")
        missing = [f for f in FIELDS if f not in OPTIONAL_FIELDS and f not in names]
        for name in missing:
            problems.append(f"{where}: missing field '{name}'")
        known = [n for n in names if n in FIELDS]
        if not missing and known != [f for f in FIELDS if f in known]:
            problems.append(f"{where}: fields out of order: {', '.join(known)} "
                            f"(expected {', '.join(FIELDS)}; After is optional)")

        expected_type = SECTION_TYPES.get(r.section)
        actual_type = r.get("Type")
        if expected_type and actual_type is not None and actual_type.strip() != expected_type:
            problems.append(f"{where}: Type '{actual_type.strip()}' does not match section "
                            f"'{r.section}' (expected '{expected_type}')")


def check_order(records, problems):
    by_slug = {r.slug: r for r in records}
    orders = {}
    for r in records:
        where = f"BOARD.md:{r.line}: '{r.slug}'"
        value = r.get("Order")
        if value is None:
            continue
        if r.order is None:
            problems.append(f"{where}: Order '{value.strip()}' is not a non-negative integer")
            continue
        if r.order in orders:
            problems.append(f"{where}: Order {r.order} is also used by '{orders[r.order]}'")
        else:
            orders[r.order] = r.slug

    for section in SECTION_TYPES:
        in_section = [r for r in records if r.section == section and r.order is not None]
        for prev, cur in zip(in_section, in_section[1:]):
            if cur.order < prev.order:
                problems.append(f"BOARD.md:{cur.line}: '{cur.slug}' (Order {cur.order}) comes after "
                                f"'{prev.slug}' (Order {prev.order}); sort the {section} section by Order")

    for r in records:
        where = f"BOARD.md:{r.line}: '{r.slug}'"
        for slug in r.after:
            if slug == r.slug:
                problems.append(f"{where}: After names the record itself")
            elif slug not in by_slug:
                problems.append(f"{where}: After '{slug}' is not a record on the board")
            elif r.order is not None and by_slug[slug].order is not None \
                    and by_slug[slug].order >= r.order:
                problems.append(f"{where}: After '{slug}' has Order {by_slug[slug].order}, "
                                f"not lower than this record's {r.order}")

    # Cycles: already ruled out when every After has a lower Order, but checked on their own
    # so the message names the cycle when the Orders are wrong too.
    graph = {r.slug: [s for s in r.after if s in by_slug and s != r.slug] for r in records}
    state = {}
    reported = set()

    def visit(slug, path):
        state[slug] = "active"
        for dep in graph.get(slug, []):
            if state.get(dep) == "active":
                cycle = path[path.index(dep):] + [dep]
                key = frozenset(cycle)
                if key not in reported:
                    reported.add(key)
                    problems.append(f"BOARD.md: After cycle: {' -> '.join(cycle)}")
            elif dep not in state:
                visit(dep, path + [dep])
        state[slug] = "done"

    for slug in graph:
        if slug not in state:
            visit(slug, [slug])


def check_line_numbers(text, problems):
    for number, line in enumerate(text.splitlines(), start=1):
        for pattern, label in LINE_NUMBER_PATTERNS:
            for match in pattern.finditer(line):
                problems.append(f"BOARD.md:{number}: {label} '{match.group(0)}'; "
                                f"refer to code by symbol, not line number")


def doc_files(root):
    files = [root / "CLAUDE.md", root / "README.md", root / "BOARD.md"]
    files += sorted((root / ".claude" / "skills").glob("**/SKILL.md"))
    files += sorted((root / "docs").glob("**/*.md"))
    return [f for f in files if f.is_file()]


def check_mentions(root, records, problems, notices):
    slugs = {r.slug for r in records}
    for path in doc_files(root):
        rel = path.relative_to(root)
        text = path.read_text(encoding="utf-8")
        for number, line in enumerate(text.splitlines(), start=1):
            for match in BOARD_MENTION_RE.finditer(line):
                for slug in BACKTICKED_RE.findall(match.group(1)):
                    if "<" in slug:
                        continue  # a placeholder such as `<slug>`
                    if slug in slugs:
                        continue
                    message = f"{rel}:{number}: board `{slug}` is not a record in BOARD.md"
                    if HISTORICAL_PLAN_DIR in rel.parents:
                        notices.append(f"notice: {message} (historical plan, not a failure)")
                    else:
                        problems.append(message)


SKIP_DIRS = {".git", "build", ".gradle", ".build", "node_modules", "DerivedData", "Pods"}


def candidate_files(root):
    """Tracked files when root is a git work tree, else a walk; fixtures and build output skipped."""
    files = []
    result = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True)
    if result.returncode == 0 and result.stdout and (root / ".git").exists():
        files = [root / name for name in result.stdout.decode("utf-8", "replace").split("\0") if name]
    else:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            files += [Path(dirpath) / name for name in filenames]
    kept = []
    for path in files:
        parts = path.relative_to(root).parts
        if any(part.endswith("-fixtures") for part in parts[:-1]) or not path.is_file():
            continue
        kept.append(path)
    return kept


def check_deleted_slugs(root, records, base_text, problems, notices):
    """A record deleted since the base: its slug must not be named in any other file."""
    base_slugs = {r.slug for r in parse_board(base_text, [])}
    gone = sorted(base_slugs - {r.slug for r in records})
    if not gone:
        return
    patterns = {slug: re.compile(r"(?<![\w-])" + re.escape(slug) + r"(?![\w-])") for slug in gone}
    for path in candidate_files(root):
        rel = path.relative_to(root)
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for number, line in enumerate(text.splitlines(), start=1):
            for slug, pattern in patterns.items():
                if pattern.search(line):
                    message = (f"{rel}:{number}: names `{slug}`, a board record deleted since the "
                               f"base; remove or reword the mention")
                    if HISTORICAL_PLAN_DIR in rel.parents:
                        notices.append(f"notice: {message} (historical plan, not a failure)")
                    else:
                        problems.append(message)


def base_board_text(root, base, base_board):
    """The old BOARD.md: from a file, from a revision, or (pull_request run without --base) from
    the base branch fetched at depth 1. None when no base applies (a local run without --base)."""
    if base_board:
        return Path(base_board).read_text(encoding="utf-8")
    if not base and os.environ.get("GITHUB_EVENT_NAME") == "pull_request" and os.environ.get("GITHUB_BASE_REF"):
        fetch = subprocess.run(["git", "-C", str(root), "fetch", "--no-tags", "--quiet", "--depth=1",
                                "origin", os.environ["GITHUB_BASE_REF"]], capture_output=True, text=True)
        if fetch.returncode != 0:
            raise RuntimeError("cannot fetch the base branch: " + fetch.stderr.strip())
        base = "FETCH_HEAD"
    if not base:
        return None
    show = subprocess.run(["git", "-C", str(root), "show", f"{base}:BOARD.md"], capture_output=True, text=True)
    if show.returncode != 0:
        raise RuntimeError(f"cannot read BOARD.md at {base}: {show.stderr.strip()}")
    return show.stdout


def next_record(records):
    open_slugs = {r.slug for r in records}
    candidates = sorted((r for r in records if r.order is not None), key=lambda r: r.order)
    for r in candidates:
        if not any(slug in open_slugs for slug in r.after if slug != r.slug):
            return r
    return None


def run_check(root, want_next, base=None, base_board=None):
    board = root / "BOARD.md"
    if not board.is_file():
        print(f"check-board: {board} not found", file=sys.stderr)
        return 2
    text = board.read_text(encoding="utf-8")
    problems = []
    notices = []
    records = parse_board(text, problems)

    if want_next:
        # Picks from the board as written; validity is the plain check's job (it runs in the
        # gate and CI), so this mode prints exactly one line or nothing.
        r = next_record(records)
        if r is None:
            print("check-board: no record can start", file=sys.stderr)
            return 1
        rtype = (r.get("Type") or "?").strip()
        suffix = ", needs an approved plan" if rtype == "epic" else ""
        print(f"{r.slug} ({rtype}, Order {r.order}{suffix})")
        return 0

    check_fields(records, problems)
    check_order(records, problems)
    check_line_numbers(text, problems)
    check_mentions(root, records, problems, notices)
    try:
        base_text = base_board_text(root, base, base_board)
    except (RuntimeError, OSError) as error:
        print(f"check-board: {error}", file=sys.stderr)
        return 2
    if base_text is not None:
        check_deleted_slugs(root, records, base_text, problems, notices)
    for notice in notices:
        print(notice)
    for problem in problems:
        print(problem)
    if problems:
        print(f"check-board: FAILED, {len(problems)} problem(s) in {len(records)} records")
        return 1
    print(f"check-board: OK, {len(records)} records")
    return 0


def self_test(script_dir):
    """Each fixture dir holds a BOARD.md (plus any docs) and an `expect` file:
    `args: ...`, `exit: N`, `contains: text` and `absent: text` lines (`{BASE}` in args is the fixture's
    `base-BOARD.md`, the BOARD.md of the base, kept out of the tree under check). A fixture's skills live
    in `dot-claude/` so Claude Code never loads them; the fixture is checked from a temporary
    copy where it is renamed to `.claude/`."""
    fixtures = sorted(p for p in (script_dir / "check-board-fixtures").iterdir() if p.is_dir())
    entry = script_dir / "check-board.sh"
    failed = 0
    for fixture in fixtures:
        args, exit_code, contains, absent = [], 0, [], []
        for line in (fixture / "expect").read_text(encoding="utf-8").splitlines():
            key, _, value = line.partition(": ")
            if key == "args":
                args = value.split()
            elif key == "exit":
                exit_code = int(value)
            elif key == "contains":
                contains.append(value)
            elif key == "absent":
                absent.append(value)
        with tempfile.TemporaryDirectory() as tmp:
            tree = Path(tmp) / fixture.name
            shutil.copytree(fixture, tree)
            if (tree / "dot-claude").is_dir():
                (tree / "dot-claude").rename(tree / ".claude")
            # The old BOARD.md and `expect` are not part of the tree under check.
            base_file = Path(tmp) / "base-BOARD.md"
            if (tree / "base-BOARD.md").exists():
                shutil.move(str(tree / "base-BOARD.md"), str(base_file))
            (tree / "expect").unlink()
            run_args = [a.replace("{BASE}", str(base_file)) for a in args]
            result = subprocess.run(["bash", str(entry), "--root", str(tree)] + run_args,
                                    capture_output=True, text=True)
        output = result.stdout + result.stderr
        errors = []
        if result.returncode != exit_code:
            errors.append(f"exit {result.returncode}, expected {exit_code}")
        errors += [f"missing: {c}" for c in contains if c not in output]
        errors += [f"unexpected: {a}" for a in absent if a in output]
        print(f"--- {fixture.name} ({' '.join(['check-board.sh'] + args)}): exit {result.returncode}")
        print("".join(f"    {line}\n" for line in output.splitlines()), end="")
        if errors:
            failed += 1
            print("".join(f"    SELF-TEST FAIL: {e}\n" for e in errors), end="")
    print(f"check-board self-test: {len(fixtures) - failed}/{len(fixtures)} fixtures passed")
    return 1 if failed else 0


def main(argv):
    script_dir = Path(__file__).resolve().parent
    root = script_dir.parent
    want_next = False
    base = None
    base_board = None
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--next":
            want_next = True
        elif arg == "--self-test":
            return self_test(script_dir)
        elif arg == "--base" and args:
            base = args.pop(0)
        elif arg == "--base-board" and args:
            base_board = args.pop(0)
        elif arg == "--root" and args:
            root = Path(args.pop(0)).resolve()
        else:
            print(f"usage: check-board.sh [--next] [--self-test] [--root <dir>] [--base <rev>] (got '{arg}')",
                  file=sys.stderr)
            return 2
    return run_check(root, want_next, base, base_board)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
