#!/usr/bin/env python3
"""Lists removed or rewritten rule lines in skills and CLAUDE.md files between two commits.

Run through scripts/check-skill-rule-changes.sh (the entry point). Standard library only, so it
runs on the stock python3 of macOS and ubuntu-latest without installing anything.

  check-skill-rule-changes.sh [--repo <dir>] <base> <head>   list the items of `git diff <base> <head>`
  check-skill-rule-changes.sh --self-test                     run the fixtures and matcher cases

Output, parsed by the reviewers, so keep it stable: the single line `none` when nothing is
listed, otherwise one line per item as `<file>:<line on the base side>: <removed text>`, sorted
by file and line. Exit 0 in both cases; exit 2 with a message on stderr for a usage or git error
(callers must treat that as a failure, never as `none`).

What is read: the diff of the two commits, for every file under `.claude/skills/` and every
file named `CLAUDE.md` (at the root or in any directory). Nothing else is read.

What is listed: every removed line (a `-` line of the diff, so a rewritten line too) that holds
a rule word: must, never, always, do not, don't, required, forbidden, only, at most, at least;
whole words, case-insensitive, the two-word ones with any whitespace between their words.
A rewritten rule line is listed whatever changed in one of its rule sentences, a number included.

What is not listed:
  - Added lines, ever.
  - A removed line of which every sentence that holds a rule word reappears unchanged, as a
    contiguous sequence of words, in the added lines of one hunk of the same file. Words are
    split on whitespace and compared exactly, punctuation included, so a moved line, a
    re-wrapped paragraph and a line whose other sentences changed pass, and a rule sentence
    with one word changed does not. Sentences without a rule word are not compared. Words
    joined across two hunks do not count, so a paragraph re-wrapped around an unchanged line
    can be listed: noise rather than a missed weakening. The listed text is the whole line.

Sentences: a sentence ends at a word that ends in `.`, `!` or `?`, optionally followed by closing
`)`, `"`, `*`, `_` or backticks. Not an end: `;`, `:` and dashes (a clause stays with its
sentence); the abbreviations e.g., i.e., etc., vs., cf. (any case, after an opening bracket,
quote or emphasis too); a mark inside an inline code span (an odd number of backticks before it
on the line, as in `try?`); a period inside a word (scripts/x.sh, 0.9.11). A Markdown list marker
at the start of the line (-, *, +, 1., 12.) is dropped and belongs to no sentence; any other
prefix (#, >, 1)) stays in the first sentence. A line that begins or ends inside a sentence (a
wrapped paragraph) holds a fragment, which is a sentence of its own. Fewer boundaries never list
less, so an unsure case is not a boundary.

Files:
  - A deleted file lists its rule lines. A rename without content change lists nothing; a
    rename with edits is diffed as one file and reported under its base path. A rename that
    moves a covered file out of the covered paths counts as a deletion of it; a rename into
    them counts as an addition.
  - Binary: a file whose base content has a NUL byte is not read; it is one item
    `<file>:-: (binary file changed or deleted; its text cannot be checked for rule words)`.
    Otherwise the diff runs with --text, so a .gitattributes in the checkout can't hide lines.
  - No trailing newline: git's "\\ No newline at end of file" marker is ignored, so a last line
    that only gains or loses its newline reappears unchanged and is not listed.
  - Control characters in a path or a line are printed as \\xNN; a line's trailing CR is dropped.

The diff options are fixed (myers, indent heuristic, no context, no external diff or textconv)
so the user's git config can't change which lines are removed.
"""

import errno
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

USAGE = "usage: check-skill-rule-changes.sh [--repo <dir>] <base> <head> | --self-test"

RULE_WORDS = re.compile(
    r"\b(?:must|never|always|do\s+not|don['’]t|required|forbidden|only|at\s+most|at\s+least)\b",
    re.IGNORECASE)

DIFF_OPTIONS = ["--no-color", "--no-ext-diff", "--no-textconv", "--no-relative",
                "--diff-algorithm=myers", "--indent-heuristic", "--inter-hunk-context=0"]

HUNK_RE = re.compile(rb"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")

BINARY_TEXT = "(binary file changed or deleted; its text cannot be checked for rule words)"

# A sentence ends at a word ending in . ! or ? plus optional closers (group 1 ends at the mark).
SENTENCE_END = re.compile(r"([.!?])[)\"*_`]*$")
OPENERS = "([\"*_`"
ABBREVIATIONS = {"e.g.", "i.e.", "etc.", "vs.", "cf."}
LIST_MARKER = re.compile(r"[-*+]|\d+\.")


class GitError(Exception):
    pass


def covered(path):
    return path.startswith(".claude/skills/") or path == "CLAUDE.md" or path.endswith("/CLAUDE.md")


def has_rule_word(text):
    return RULE_WORDS.search(text) is not None


def printable(text):
    return "".join(c if c == "\t" or (32 <= ord(c) != 127) else f"\\x{ord(c):02x}" for c in text)


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


def changed_entries(repo, base, head):
    """Yields (status, old path, old blob, new path) for every entry of the raw diff."""
    raw = git(repo, ["diff", "--raw", "-z", "--no-abbrev", "--find-renames"] + DIFF_OPTIONS
                    + [base, head])
    tokens = raw.split(b"\0")
    i = 0
    while i < len(tokens) and tokens[i]:
        meta = tokens[i].decode("ascii").split()
        status = meta[4][0]
        old_blob = meta[2]
        if status in "RC":
            old, new = tokens[i + 1], tokens[i + 2]
            i += 3
        else:
            old = new = tokens[i + 1]
            i += 2
        yield status, old.decode("utf-8", "surrogateescape"), old_blob, \
            new.decode("utf-8", "surrogateescape")


def parse_patch(patch):
    """Returns (removed, added_hunks): removed is [(base line, text)], added_hunks is a list of
    word lists, one per hunk."""
    removed, added_hunks = [], []
    old_left = new_left = 0
    old_line = 0
    words = None
    for raw in patch.split(b"\n"):
        if old_left == 0 and new_left == 0:
            match = HUNK_RE.match(raw)
            if match:
                old_line = int(match.group(1))
                old_left = int(match.group(2)) if match.group(2) is not None else 1
                new_left = int(match.group(4)) if match.group(4) is not None else 1
                words = []
                added_hunks.append(words)
            continue
        text = raw[1:].decode("utf-8", "replace")
        if raw.startswith(b"\\"):
            continue  # "\ No newline at end of file"
        if raw.startswith(b"-"):
            removed.append((old_line, text))
            old_line += 1
            old_left -= 1
        elif raw.startswith(b"+"):
            words.extend(text.split())
            new_left -= 1
        elif raw.startswith(b" "):
            old_line += 1
            old_left -= 1
            new_left -= 1
        else:
            raise GitError("unexpected line in a diff hunk")
    if old_left or new_left:
        raise GitError("the diff ended inside a hunk")
    return removed, added_hunks


def contains_run(haystack, needle):
    n = len(needle)
    return any(haystack[i:i + n] == needle for i in range(len(haystack) - n + 1))


def ends_sentence(word, backticks_before):
    """True when `word` ends a sentence: it ends in `.`, `!` or `?`, optionally followed by
    closing `)`, `"`, `*`, `_` or backticks, is not one of ABBREVIATIONS, and the mark is not
    inside an inline code span (an odd number of backticks before it on the line, as in `try?`)."""
    match = SENTENCE_END.search(word)
    if not match:
        return False
    if (backticks_before + word[:match.start()].count("`")) % 2:
        return False
    return word[:match.end(1)].lstrip(OPENERS).lower() not in ABBREVIATIONS


def sentences(text):
    """Splits a removed line into sentences, each a list of words (split on whitespace). A
    leading Markdown list marker is dropped; a fragment at either end of the line is a sentence
    of its own. Fewer boundaries never list less, so anything unsure is not a boundary."""
    words = text.split()
    if words and LIST_MARKER.fullmatch(words[0]):
        words = words[1:]
    result, current, backticks = [], [], 0
    for word in words:
        current.append(word)
        if ends_sentence(word, backticks):
            result.append(current)
            current = []
        backticks += word.count("`")
    if current:
        result.append(current)
    return result


def retained(text, added_hunks):
    """True when every sentence of the line that holds a rule word reappears, as a contiguous
    word sequence, in the added words of one hunk. A line whose rule word is in no sentence (it
    can't happen, the split keeps every word but a list marker) is not retained."""
    rule_sentences = [s for s in sentences(text) if has_rule_word(" ".join(s))]
    return bool(rule_sentences) and all(
        any(contains_run(hunk, sentence) for hunk in added_hunks) for sentence in rule_sentences)


def items_for(repo, base, head, status, old, old_blob, new):
    """The listed items of one raw diff entry, as (path, line, text)."""
    if status == "A" or not covered(old):
        return []  # an addition, or a rename into the covered paths
    if b"\0" in git(repo, ["cat-file", "blob", old_blob]):
        return [(old, None, BINARY_TEXT)]
    if status in "RC" and covered(new):
        paths, renames = ["--", old, new], ["--find-renames"]
    else:
        paths, renames = ["--", old], ["--no-renames"]  # a deletion, or a rename out
    patch = git(repo, ["diff", "--text", "-U0"] + renames + DIFF_OPTIONS + [base, head] + paths)
    removed, added_hunks = parse_patch(patch)
    items = []
    for line, text in removed:
        if not has_rule_word(text):
            continue
        if retained(text, added_hunks):
            continue
        items.append((old, line, text[:-1] if text.endswith("\r") else text))
    return items


def list_items(repo, base, head):
    base, head = resolve(repo, base), resolve(repo, head)
    items = []
    for status, old, old_blob, new in changed_entries(repo, base, head):
        items.extend(items_for(repo, base, head, status, old, old_blob, new))
    items.sort(key=lambda item: (item[0], item[1] or 0))
    return [f"{printable(path)}:{'-' if line is None else line}: {printable(text)}"
            for path, line, text in items] or ["none"]


# --- self-test ------------------------------------------------------------------------------

# (text, expected): whole words, case-insensitive.
MATCH_CASES = [
    ("You must run the gate.", True),
    ("MUST", True),
    ("Never push to main.", True),
    ("always", True),
    ("Do not edit it.", True),
    ("do\tnot", True),
    ("Don't edit it.", True),
    ("Don’t edit it.", True),
    ("required checks", True),
    ("forbidden", True),
    ("read-only reviewer", True),
    ("at most two", True),
    ("At  least one", True),
    ("mustard and musty", False),
    ("commonly, onlyfans", False),
    ("nevertheless", False),
    ("requirement", False),
    ("do nothing", False),
    ("at mostly", False),
    ("a number: 15 minutes", False),
]

# (line, its sentences joined with " | "): the sentence split of a removed line.
SPLIT_CASES = [
    ("Always run the gate. Never push to `main`.", "Always run the gate. | Never push to `main`."),
    ("Is it done? Push it! Then stop.", "Is it done? | Push it! | Then stop."),
    ("Never push to `main`; work on a branch: always.", "Never push to `main`; work on a branch: always."),
    ("Never push - not even once.", "Never push - not even once."),
    ("- Never push.", "Never push."),
    ("* Never push.", "Never push."),
    ("+ Never push.", "Never push."),
    ("3. Never push.", "Never push."),
    ("12. Never push. Use a branch.", "Never push. | Use a branch."),
    ("1) Never push.", "1) Never push."),
    ("# Never push.", "# Never push."),
    ("> Never push.", "> Never push."),
    ("Never add a library, e.g. MockK, here.", "Never add a library, e.g. MockK, here."),
    ("Use fakes (i.e. no mocks), etc. vs. stubs, cf. tm-testing.",
     "Use fakes (i.e. no mocks), etc. vs. stubs, cf. tm-testing."),
    ("E.g. this. I.E. that.", "E.g. this. | I.E. that."),
    ("Lists (a, b, etc.) end here. Next.", "Lists (a, b, etc.) end here. | Next."),
    ("Lists a, b, etc.). Next.", "Lists a, b, etc.). | Next."),
    ("Run scripts/x.sh in 0.9.11 builds. Done.", "Run scripts/x.sh in 0.9.11 builds. | Done."),
    ("**Never push.** (Use a branch.) \"Stop.\" _Wait._ `Run it`. Done",
     "**Never push.** | (Use a branch.) | \"Stop.\" | _Wait._ | `Run it`. | Done"),
    ("Never use `try?` outside tests.", "Never use `try?` outside tests."),
    ("Never use `x. y` here. Done.", "Never use `x. y` here. | Done."),
    ("Say 'stop.' Then go.", "Say 'stop.' Then go."),
    ("then completes; it never throws. iOS consumes that; Android",
     "then completes; it never throws. | iOS consumes that; Android"),
    ("-", ""),
]

FIXTURES = "check-skill-rule-changes-fixtures"


def fake_rmtree(errors, always=False):
    """An rmtree that raises `errors` one per call, then succeeds, or with `always` keeps raising
    the last one. Returns it and the list of paths it was called with."""
    calls = []

    def rmtree(path):
        calls.append(path)
        if len(calls) <= len(errors) or always:
            raise errors[min(len(calls), len(errors)) - 1]
    return rmtree, calls


def enotempty():
    return OSError(errno.ENOTEMPTY, os.strerror(errno.ENOTEMPTY))


def check_retries_then_succeeds():
    rmtree, calls = fake_rmtree([enotempty(), enotempty()])
    sleeps = []
    try:
        remove_scratch("/scratch/x", rmtree=rmtree, sleep=sleeps.append)
    except OSError as error:
        return f"raised {error!r}"
    if len(calls) != 3 or len(sleeps) != 2:
        return f"{len(calls)} rmtree calls and {len(sleeps)} sleeps, expected 3 and 2"
    return ""


def check_gives_up_and_names_what_is_left():
    tmp = tempfile.mkdtemp(prefix="tm-rule-changes-left-")
    try:
        (Path(tmp) / ".git").mkdir()
        (Path(tmp) / ".git" / "gc.pid").write_text("1\n")
        rmtree, _ = fake_rmtree([enotempty()], always=True)
        try:
            remove_scratch(tmp, rmtree=rmtree, sleep=lambda _: None)
        except OSError as error:
            message = str(error)
            if error.errno != errno.ENOTEMPTY or tmp not in message \
                    or os.path.join(".git", "gc.pid") not in message:
                return f"error does not name the path and the file left: {message!r}"
            return ""
        return "returned, expected an OSError"
    finally:
        shutil.rmtree(tmp)


def check_other_error_raised_at_once():
    rmtree, calls = fake_rmtree([PermissionError(errno.EACCES, os.strerror(errno.EACCES))])
    sleeps = []
    try:
        remove_scratch("/scratch/x", rmtree=rmtree, sleep=sleeps.append)
    except PermissionError:
        if len(calls) != 1 or sleeps:
            return f"{len(calls)} rmtree calls and {len(sleeps)} sleeps, expected 1 and 0"
        return ""
    except OSError as error:
        return f"raised {error!r}, expected the PermissionError"
    return "returned, expected the PermissionError"


REMOVE_SCRATCH_CASES = [
    ("ENOTEMPTY twice, then removed: returns after 2 sleeps", check_retries_then_succeeds),
    ("ENOTEMPTY every time: raises, naming the path and what is left",
     check_gives_up_and_names_what_is_left),
    ("PermissionError: raised at once, no sleep", check_other_error_raised_at_once),
]


def fixture_path(rel):
    """Fixture trees spell `.claude` as `dot-claude` and `CLAUDE.md` as `CLAUDE.md.fixture`,
    so no agent tool picks them up as real instructions."""
    parts = ["." + p[4:] if p.startswith("dot-") else p for p in rel.parts]
    if parts[-1] == "CLAUDE.md.fixture":
        parts[-1] = "CLAUDE.md"
    return Path(*parts)


def self_git(repo, *args):
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=self-test",
                    "-c", "user.email=self-test@example.invalid", "-c", "commit.gpgsign=false",
                    "-c", "gc.auto=0", "-c", "maintenance.auto=false"]
                   + list(args), check=True, capture_output=True)


def remove_scratch(path, rmtree=shutil.rmtree, sleep=time.sleep, attempts=5):
    """Removes a scratch directory. Only `Directory not empty` (ENOTEMPTY) is retried, after 0.2
    seconds: something may still be writing into it (one CI run failed this way; the writer is
    unknown). Any other error is raised at once. When every attempt fails, the error names the
    path and what is left under it (at most 50 relative paths), so a CI log shows it."""
    for attempt in range(attempts):
        if attempt:
            sleep(0.2)
        try:
            rmtree(path)
            return
        except OSError as error:
            if error.errno != errno.ENOTEMPTY:
                raise
            last = error
    left = []
    for root, dirs, files in os.walk(path):
        dirs.sort()
        left += [os.path.relpath(os.path.join(root, name), path) for name in dirs + sorted(files)]
        if len(left) > 50:
            break
    shown = ", ".join(left[:50]) + (", ..." if len(left) > 50 else "")
    raise OSError(errno.ENOTEMPTY, f"cannot remove {path} after {attempts} attempts ({last}); "
                                   f"still present: {shown or 'nothing'}") from last


def commit_tree(repo, tree, message):
    for child in repo.iterdir():
        if child.name != ".git":
            subprocess.run(["rm", "-rf", "--", str(child)], check=True)
    if tree.is_dir():
        for src in sorted(p for p in tree.rglob("*") if p.is_file()):
            dst = repo / fixture_path(src.relative_to(tree))
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(src.read_bytes())
    self_git(repo, "add", "-A")
    self_git(repo, "commit", "-q", "--allow-empty", "-m", message)
    return subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], check=True,
                          capture_output=True, text=True).stdout.strip()


def run_fixture(entry, fixture):
    """`base/` and `head/` trees, `expect` (`exit: N`, optional `stderr: <text>` lines that
    stderr must contain), `stdout` (exact; absent means empty), optional `args` (one line,
    BASE and HEAD stand for the two commits; default `BASE HEAD`)."""
    expect = {"exit": None, "stderr": []}
    for line in (fixture / "expect").read_text(encoding="utf-8").splitlines():
        key, _, value = line.partition(": ")
        if key == "exit":
            expect["exit"] = int(value)
        elif key == "stderr":
            expect["stderr"].append(value)
        elif line.strip():
            raise ValueError(f"{fixture.name}/expect: unknown line '{line}'")
    if expect["exit"] is None:
        raise ValueError(f"{fixture.name}/expect: no 'exit:' line")
    stdout_file = fixture / "stdout"
    want_stdout = stdout_file.read_text(encoding="utf-8") if stdout_file.exists() else ""
    args_file = fixture / "args"
    args = args_file.read_text(encoding="utf-8").split() if args_file.exists() else ["BASE", "HEAD"]
    tmp = tempfile.mkdtemp(prefix="tm-rule-changes-")
    try:
        repo = Path(tmp)
        self_git(repo, "init", "-q")
        shas = {"BASE": commit_tree(repo, fixture / "base", "base"),
                "HEAD": commit_tree(repo, fixture / "head", "head")}
        args = [shas.get(a, a) for a in args]
        env = dict(os.environ, LC_ALL="C")
        result = subprocess.run(["bash", str(entry), "--repo", str(repo)] + args,
                                capture_output=True, text=True, env=env)
        output = result.stdout.replace(shas["BASE"], "<base>").replace(shas["HEAD"], "<head>")
        err = result.stderr.replace(shas["BASE"], "<base>").replace(shas["HEAD"], "<head>")
    finally:
        remove_scratch(tmp)
    errors = []
    if result.returncode != expect["exit"]:
        errors.append(f"exit {result.returncode}, expected {expect['exit']}")
    if output != want_stdout:
        errors.append(f"stdout {output!r}, expected {want_stdout!r}")
    errors += [f"stderr is missing: {s}" for s in expect["stderr"] if s not in err]
    return errors, result.returncode, output + err


def self_test(script_dir):
    failed = total = 0
    print("--- rule-word matcher")
    for text, expected in MATCH_CASES:
        total += 1
        actual = has_rule_word(text)
        failed += actual != expected
        print(f"    {'ok  ' if actual == expected else 'FAIL'} {text!r:32} expected {expected}, got {actual}")
    print("--- sentence split")
    for text, expected in SPLIT_CASES:
        total += 1
        actual = " | ".join(" ".join(s) for s in sentences(text))
        failed += actual != expected
        print(f"    {'ok  ' if actual == expected else 'FAIL'} {text!r}"
              + ("" if actual == expected else f"\n         expected {expected!r}, got {actual!r}"))
    print("--- remove_scratch (injected rmtree and sleep)")
    for name, check in REMOVE_SCRATCH_CASES:
        total += 1
        problem = check()
        failed += bool(problem)
        print(f"    {'FAIL' if problem else 'ok  '} {name}" + (f": {problem}" if problem else ""))

    fixtures = script_dir / FIXTURES
    entry = script_dir / "check-skill-rule-changes.sh"
    print(f"--- fixtures ({FIXTURES}/, scripts/check-skill-rule-changes.sh in a temporary git repo)")
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
        failed += 1
        print(f"    FAIL no fixtures found in {fixtures}")
    print(f"check-skill-rule-changes self-test: {total - failed}/{total} cases passed")
    return 1 if failed else 0


def main(argv):
    script_dir = Path(__file__).resolve().parent
    repo = Path.cwd()
    args = list(argv)
    if args == ["--self-test"]:
        return self_test(script_dir)
    if len(args) >= 2 and args[0] == "--repo":
        repo = Path(args[1])
        args = args[2:]
    if len(args) != 2 or any(a.startswith("-") or not a for a in args):
        print(f"{USAGE} (got {' '.join(argv) or 'no arguments'})", file=sys.stderr)
        return 2
    try:
        lines = list_items(repo, args[0], args[1])
    except GitError as error:
        print(f"check-skill-rule-changes: {error}", file=sys.stderr)
        return 2
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
