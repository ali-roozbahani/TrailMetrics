#!/usr/bin/env python3
"""Self-test of the reviewer workflow's retry and verdict mapping.

Run through scripts/check-pr-review-workflow.sh (the entry point). Standard library only, so
it runs on the stock python3 of macOS and ubuntu-latest without installing anything.

  check-pr-review-workflow.sh --self-test                    test the committed workflow
  check-pr-review-workflow.sh --self-test --workflow <file>  test another copy of it (used to
                                                             show the test going red on an
                                                             older or broken version)

What it does, per run:
  1. Extracts, from the workflow file itself, the `run:` scripts of the steps "Run
     pr-reviewer" and "Map verdict" and the workflow's literal `env:` (REVIEW_MODEL and
     REVIEW_MAX_TURNS are required), with the small YAML-subset parser below. It fails when a
     step is missing or appears twice, its `run:` is empty, a script contains a GitHub
     expression (`${{`, which this harness cannot evaluate), or the steps use something the
     harness does not emulate (`shell:`, `defaults:`, `working-directory:`,
     `continue-on-error:`, an `if:` other than none, success(), always() or !cancelled()).
     The cases in fixtures/extractor/ show each of these failing.
  2. Runs every scenario in fixtures/scenarios/ in its own scratch directory: a stub
     `claude` at $RUNNER_TEMP/claude-cli/node_modules/.bin/claude answers each call as the
     scenario's `stub` file says and logs a hash of its stdin, its arguments and its working
     directory. The two scripts run as GitHub runs a `run:` without `shell:` (`bash -e
     <file>`, bash from PATH), one after the other, the second as its `if:` allows.
  3. Checks the scenario's `expect` file: number of reviewer calls (two calls must have the
     same stdin, arguments and directory), exactly one workflow command titled
     `Review — pr-reviewer` with its level and message start, every other log line starting
     with `::` listed as `command:`, the job result, the "Attempt 2 of 2" summary line if and
     only if there were two calls, and each report's marker in the summary where listed and
     never in the log.

Nothing here prints a raw log line: log lines appear only after a `log> ` prefix, so a
workflow command in a report can never be processed by the runner that runs this test.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

RUN_STEP = "Run pr-reviewer"
MAP_STEP = "Map verdict"
REQUIRED_ENV = ("REVIEW_MODEL", "REVIEW_MAX_TURNS")
TITLE = "Review — pr-reviewer"
HEAD_SHA = "0123456789abcdef0123456789abcdef01234567"
PR_TEXT_MARKER = "ZQXPRTEXTMARKER"
STEP_TIMEOUT = 60

# Step env values that are GitHub expressions get a scratch value; "ANTHROPIC_API_KEY" is
# set or empty per scenario.
SCRATCH_STEP_ENV = {"ANTHROPIC_API_KEY", "HEAD_SHA"}
IF_ALWAYS = {"always()", "!cancelled()"}
IF_SUCCESS = {"success()"}
UNSUPPORTED_STEP_KEYS = ("shell", "working-directory", "continue-on-error")


class ExtractError(Exception):
    pass


# --- A YAML subset: block mappings, block sequences, plain and quoted scalars, literal
# block scalars (|, |-, |+). Flow collections ([a, b]) stay raw strings. Anything else that
# the workflow would need is rejected, not guessed.

KEY_RE = re.compile(r"""^("[^"]*"|'[^']*'|[^\s'"#:][^:]*?):(?:[ \t]+(.*))?$""")


def _indent(line):
    stripped = line.lstrip(" ")
    if stripped.startswith("\t"):
        raise ExtractError("a tab in the indentation is not supported")
    return len(line) - len(stripped)


def _is_content(line):
    s = line.strip()
    return bool(s) and not s.startswith("#")


def _scalar(text, where):
    text = text.strip()
    if text[:1] in ("'", '"'):
        quote = text[0]
        end = text.find(quote, 1)
        while quote == "'" and end != -1 and text[end + 1:end + 2] == "'":
            end = text.find(quote, end + 2)
        if end == -1:
            raise ExtractError(f"{where}: unterminated quoted value")
        rest = text[end + 1:].strip()
        if rest and not rest.startswith("#"):
            raise ExtractError(f"{where}: text after a quoted value")
        inner = text[1:end]
        if quote == '"' and "\\" in inner:
            raise ExtractError(f"{where}: escapes in double-quoted values are not supported")
        return inner.replace("''", "'") if quote == "'" else inner
    if text[:1] in (">", "&", "*", "!"):
        raise ExtractError(f"{where}: '{text[0]}' values are not supported")
    match = re.search(r"\s#", text)
    return text[:match.start()].rstrip() if match else text


class _Parser:
    def __init__(self, text):
        self.lines = text.split("\n")
        self.i = 0

    def where(self):
        return f"workflow line {self.i + 1}"

    def skip(self):
        while self.i < len(self.lines) and not _is_content(self.lines[self.i]):
            self.i += 1

    def node(self, min_indent):
        self.skip()
        if self.i >= len(self.lines) or _indent(self.lines[self.i]) < min_indent:
            return None
        ind = _indent(self.lines[self.i])
        if self.lines[self.i].strip() == "-" or self.lines[self.i].strip().startswith("- "):
            return self.seq(ind)
        return self.mapping(ind)

    def seq(self, ind):
        items = []
        while True:
            self.skip()
            if self.i >= len(self.lines):
                break
            line = self.lines[self.i]
            if _indent(line) != ind or not (line.strip() == "-" or line.strip().startswith("- ")):
                if _indent(line) > ind:
                    raise ExtractError(f"{self.where()}: unexpected indentation")
                break
            rest = line.strip()[1:]
            if not rest.strip() or rest.strip().startswith("#"):
                self.i += 1
                items.append(self.node(ind + 1))
                continue
            col = ind + 1 + (len(rest) - len(rest.lstrip(" ")))
            if KEY_RE.match(rest.strip()):
                # "- key: value" is a mapping whose keys sit at the column after "- ".
                self.lines[self.i] = " " * col + rest.strip()
                items.append(self.mapping(col))
            else:
                items.append(_scalar(rest, self.where()))
                self.i += 1
        return items

    def mapping(self, ind):
        result = {}
        while True:
            self.skip()
            if self.i >= len(self.lines):
                break
            line = self.lines[self.i]
            if _indent(line) < ind:
                break
            if _indent(line) > ind:
                raise ExtractError(f"{self.where()}: unexpected indentation")
            text = line.strip()
            if text == "-" or text.startswith("- "):
                break
            match = KEY_RE.match(text)
            if not match:
                raise ExtractError(f"{self.where()}: not a 'key: value' line")
            key = _scalar(match.group(1), self.where())
            rest = match.group(2)
            if key in result:
                raise ExtractError(f"{self.where()}: duplicate key '{key}'")
            if rest is None or not rest.strip() or rest.strip().startswith("#"):
                self.i += 1
                self.skip()
                nxt = self.lines[self.i] if self.i < len(self.lines) else ""
                if self.i < len(self.lines) and _indent(nxt) == ind and (
                        nxt.strip() == "-" or nxt.strip().startswith("- ")):
                    value = self.seq(ind)
                else:
                    value = self.node(ind + 1)
            elif rest.strip()[:1] in ("|", ">"):
                value = self.block(rest.strip(), ind)
            else:
                value = _scalar(rest, self.where())
                self.i += 1
            result[key] = value
        return result

    def block(self, header, ind):
        header = re.sub(r"\s+#.*$", "", header)
        if header not in ("|", "|-", "|+"):
            raise ExtractError(f"{self.where()}: block scalar '{header}' is not supported "
                               "(only |, |- and |+)")
        self.i += 1
        body = []
        content_indent = None
        while self.i < len(self.lines):
            line = self.lines[self.i]
            if line.strip():
                if content_indent is None:
                    content_indent = _indent(line)
                    if content_indent <= ind:
                        break
                elif _indent(line) < content_indent:
                    break
            body.append(line)
            self.i += 1
        if content_indent is None or content_indent <= ind:
            body = []
        text_lines = [b[content_indent:] if b.strip() else "" for b in body]
        while text_lines and not text_lines[-1]:
            text_lines.pop()
        if not text_lines:
            return ""
        text = "\n".join(text_lines)
        return text if header == "|-" else text + "\n"


def parse_yaml(text):
    lines = text.split("\n")
    if lines and lines[0].strip() == "---":
        lines[0] = ""
    parser = _Parser("\n".join(lines))
    doc = parser.node(0)
    parser.skip()
    if parser.i < len(parser.lines):
        raise ExtractError(f"{parser.where()}: unexpected text at the top level")
    return doc


# --- Extraction

def _literal_env(block, where):
    if block is None:
        return {}
    if not isinstance(block, dict):
        raise ExtractError(f"{where} env: is not a mapping")
    env = {}
    for key, value in block.items():
        if not isinstance(value, str):
            raise ExtractError(f"{where} env {key}: is not a scalar")
        if "${{" in value:
            raise ExtractError(f"{where} env {key}: contains a GitHub expression, which the "
                               "harness cannot evaluate")
        env[key] = value
    return env


def _if_mode(step, name):
    cond = step.get("if")
    if cond is None:
        return "success"
    if not isinstance(cond, str):
        raise ExtractError(f"step '{name}': if: is not a scalar")
    expr = cond.strip()
    if expr.startswith("${{") and expr.endswith("}}"):
        expr = expr[3:-2].strip()
    if expr in IF_ALWAYS:
        return "always"
    if expr in IF_SUCCESS:
        return "success"
    raise ExtractError(f"step '{name}': if: {cond} is not supported by the harness "
                       "(only none, success(), always() or !cancelled())")


def extract(path):
    try:
        text = Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        raise ExtractError(f"cannot read {path}: {e}")
    doc = parse_yaml(text)
    if not isinstance(doc, dict):
        raise ExtractError("the workflow is not a mapping")
    if "defaults" in doc:
        raise ExtractError("workflow-level defaults: is not supported (the harness runs "
                           "GitHub's default shell)")
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict):
        raise ExtractError("the workflow has no jobs: mapping")

    found = {RUN_STEP: [], MAP_STEP: []}
    for job_id, job in jobs.items():
        steps = job.get("steps") if isinstance(job, dict) else None
        for index, step in enumerate(steps if isinstance(steps, list) else []):
            if isinstance(step, dict) and step.get("name") in found:
                found[step["name"]].append((job_id, index, step))
    for name, hits in found.items():
        if not hits:
            raise ExtractError(f"step '{name}' not found")
        if len(hits) > 1:
            raise ExtractError(f"step '{name}' appears {len(hits)} times")
    (run_job, run_index, run_step), = found[RUN_STEP]
    (map_job, map_index, map_step), = found[MAP_STEP]
    if run_job != map_job:
        raise ExtractError(f"steps '{RUN_STEP}' and '{MAP_STEP}' are in different jobs")
    if run_index > map_index:
        raise ExtractError(f"step '{MAP_STEP}' comes before '{RUN_STEP}'")
    job = jobs[run_job]
    if "defaults" in job:
        raise ExtractError(f"job '{run_job}': defaults: is not supported (the harness runs "
                           "GitHub's default shell)")

    env = _literal_env(doc.get("env"), "workflow")
    env.update(_literal_env(job.get("env"), f"job '{run_job}'"))
    for key in REQUIRED_ENV:
        if not env.get(key):
            raise ExtractError(f"{key} not found in the workflow's or the job's env:")

    steps = {}
    for name, step in ((RUN_STEP, run_step), (MAP_STEP, map_step)):
        for key in UNSUPPORTED_STEP_KEYS:
            if key in step:
                raise ExtractError(f"step '{name}': {key}: is not supported by the harness")
        script = step.get("run")
        if not isinstance(script, str) or not script.strip():
            raise ExtractError(f"step '{name}': its run: block is empty")
        if "${{" in script:
            raise ExtractError(f"step '{name}': its run: script contains a GitHub expression "
                               "(${{), which the harness cannot evaluate")
        step_env = {}
        raw_env = step.get("env") or {}
        if not isinstance(raw_env, dict):
            raise ExtractError(f"step '{name}': env: is not a mapping")
        for key, value in raw_env.items():
            if not isinstance(value, str):
                raise ExtractError(f"step '{name}' env {key}: is not a scalar")
            if "${{" in value and key not in SCRATCH_STEP_ENV:
                raise ExtractError(f"step '{name}' env {key}: a GitHub expression with no "
                                   "scratch value in the harness")
            step_env[key] = None if "${{" in value else value
        steps[name] = {"script": script, "env": step_env, "if": _if_mode(step, name)}
    return {"env": env, "steps": steps}


# --- The stub `claude` CLI. It reads its answers from ../../stub/calls.json (relative to
# node_modules/.bin), appends one JSON line per call to ../../stub/calls.log and answers
# call N with spec N: a JSON result, or raw output, and an exit code.

STUB = r'''
import hashlib, json, os, sys
from pathlib import Path
state = Path(__file__).resolve().parents[2] / "stub"
specs = json.loads((state / "calls.json").read_text(encoding="utf-8"))
log = state / "calls.log"
n = len(log.read_text(encoding="utf-8").splitlines()) + 1 if log.exists() else 1
stdin = sys.stdin.buffer.read()
entry = {
    "call": n,
    "stdin": hashlib.sha256(stdin).hexdigest(),
    "args": hashlib.sha256("\0".join(sys.argv[1:]).encode("utf-8")).hexdigest(),
    "cwd": os.getcwd(),
}
with log.open("a", encoding="utf-8") as f:
    f.write(json.dumps(entry) + "\n")
if n > len(specs):
    print(json.dumps({"type": "result", "subtype": "error", "is_error": True,
                      "result": "stub: no answer for call %d" % n}))
    sys.exit(3)
spec = specs[n - 1]
if spec["raw"] is not None:
    sys.stdout.write(spec["raw"])
else:
    answer = {"type": "result", "subtype": spec["subtype"], "is_error": spec["is_error"],
              "num_turns": 18, "total_cost_usd": 0.42}
    if spec["report"] is not None:
        answer["result"] = spec["report"]
    print(json.dumps(answer))
sys.exit(spec["exit"])
'''


# --- Fixtures

def _marker(scenario, n):
    return f"ZQXREPORTMARKER{n}-{scenario}"


def load_scenario(fixture):
    """`stub`: `api-key: set|empty` and one `call:` line per answer, in call order, with
    `exit=N`, optional `is_error=true|false` (default false), `subtype=...` (default
    success) and either `report=<file>`, `report=empty-string`, `report=absent` (a JSON
    result with no `result` field) or `output=<file>` (raw stdout, not JSON). Report files use @@HEAD_SHA@@ and @@MARKER@@; every non-empty
    report must contain @@MARKER@@.
    `expect`: `calls: N`, `annotation: <notice|warning|error> <message start>`,
    `job: pass|fail`, `in-summary: <call numbers>|none`, and `command: <line>` for each
    other workflow command the log must have exactly once."""
    name = fixture.name
    api_key, calls = None, []
    for line in (fixture / "stub").read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        key, _, value = line.partition(": ")
        if key == "api-key" and value in ("set", "empty"):
            api_key = value == "set"
        elif key == "call":
            fields = dict(tok.split("=", 1) for tok in value.split())
            n = len(calls) + 1
            spec = {"exit": int(fields["exit"]), "is_error": fields.get("is_error", "false") == "true",
                    "subtype": fields.get("subtype", "success"), "report": None, "raw": None}
            if "output" in fields:
                spec["raw"] = _fill(fixture / fields["output"], name, n, fixture)
            elif fields.get("report") == "empty-string":
                spec["report"] = ""
            elif fields.get("report") == "absent":
                pass
            elif "report" in fields:
                spec["report"] = _fill(fixture / fields["report"], name, n, fixture)
            else:
                raise ValueError(f"{fixture.name}/stub: call {n} has no report= or output=")
            calls.append(spec)
        else:
            raise ValueError(f"{fixture.name}/stub: unknown line '{line}'")
    if api_key is None:
        raise ValueError(f"{fixture.name}/stub: no 'api-key: set|empty' line")

    expect = {"calls": None, "annotation": None, "job": None, "in_summary": None, "commands": []}
    for line in (fixture / "expect").read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        key, _, value = line.partition(": ")
        if key == "calls":
            expect["calls"] = int(value)
        elif key == "annotation":
            level, _, start = value.partition(" ")
            if level not in ("notice", "warning", "error") or not start:
                raise ValueError(f"{fixture.name}/expect: bad annotation line '{line}'")
            expect["annotation"] = (level, start)
        elif key == "job" and value in ("pass", "fail"):
            expect["job"] = value
        elif key == "in-summary":
            expect["in_summary"] = set() if value == "none" else {int(v) for v in value.split()}
        elif key == "command":
            expect["commands"].append(value)
        else:
            raise ValueError(f"{fixture.name}/expect: unknown line '{line}'")
    for key in ("calls", "annotation", "job", "in_summary"):
        if expect[key] is None:
            raise ValueError(f"{fixture.name}/expect: '{key.replace('_', '-')}' is missing")
    return api_key, calls, expect


def _fill(path, scenario, n, fixture):
    text = path.read_text(encoding="utf-8")
    if text.strip() and "@@MARKER@@" not in text:
        raise ValueError(f"{fixture.name}/{path.name}: a non-empty report needs @@MARKER@@")
    return text.replace("@@MARKER@@", _marker(scenario, n)).replace("@@HEAD_SHA@@", HEAD_SHA)


def _parse_command(line):
    """`::name params::message` -> (name, {param: value}, message), else None."""
    match = re.match(r"^::([A-Za-z-]+)(?: ([^:]*))?::(.*)$", line)
    if not match:
        return None
    params = {}
    for part in (match.group(2) or "").split(","):
        key, sep, value = part.partition("=")
        if sep:
            params[key.strip()] = value
    return match.group(1), params, match.group(3)


def run_scenario(fixture, extracted, bash):
    api_key, calls, expect = load_scenario(fixture)
    name = fixture.name
    with tempfile.TemporaryDirectory(prefix="tm-pr-review-") as tmp:
        tmp = Path(tmp)
        runner_temp = tmp / "runner"
        work = runner_temp / "review"
        (work / "tree").mkdir(parents=True)
        (work / "input").mkdir()
        (work / "message").write_text(
            f"SHA: {HEAD_SHA}\nTASK:\n--- PR description (author-written) ---\n"
            f"{PR_TEXT_MARKER} {name}\n--- end of PR description ---\n", encoding="utf-8")
        state = runner_temp / "claude-cli" / "stub"
        state.mkdir(parents=True)
        (state / "calls.json").write_text(json.dumps(calls), encoding="utf-8")
        bin_dir = runner_temp / "claude-cli" / "node_modules" / ".bin"
        bin_dir.mkdir(parents=True)
        stub = bin_dir / "claude"
        stub.write_text(f"#!{sys.executable}\n{STUB}", encoding="utf-8")
        stub.chmod(0o755)
        workspace = tmp / "workspace"
        workspace.mkdir()
        home = tmp / "home"
        home.mkdir()
        summary = tmp / "summary.md"
        summary.write_text("", encoding="utf-8")

        scratch = {"ANTHROPIC_API_KEY": "scratch-key" if api_key else "", "HEAD_SHA": HEAD_SHA}
        base_env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(home),
                    "TMPDIR": str(tmp), "RUNNER_TEMP": str(runner_temp),
                    "GITHUB_STEP_SUMMARY": str(summary)}
        base_env.update(extracted["env"])

        log, results, ok_so_far = "", {}, True
        for step_name in (RUN_STEP, MAP_STEP):
            step = extracted["steps"][step_name]
            if step["if"] == "success" and not ok_so_far:
                results[step_name] = None
                continue
            env = dict(base_env)
            for key, value in step["env"].items():
                env[key] = scratch[key] if value is None else value
            script = tmp / f"step-{len(results) + 1}.sh"
            script.write_text(step["script"], encoding="utf-8")
            try:
                proc = subprocess.run([bash, "-e", str(script)], cwd=workspace, env=env,
                                      stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT, timeout=STEP_TIMEOUT)
                code = proc.returncode
                log += proc.stdout.decode("utf-8", errors="replace")
            except subprocess.TimeoutExpired:
                code = "timeout"
            results[step_name] = code
            ok_so_far = ok_so_far and code == 0
        summary_text = summary.read_text(encoding="utf-8", errors="replace")
        call_log = state / "calls.log"
        entries = [json.loads(l) for l in call_log.read_text(encoding="utf-8").splitlines()] \
            if call_log.exists() else []

    errors = []
    if len(entries) != expect["calls"]:
        errors.append(f"reviewer calls {len(entries)}, expected {expect['calls']}")
    for key in ("stdin", "args", "cwd"):
        if len({e[key] for e in entries}) > 1:
            errors.append(f"the calls got different {key}")

    log_lines = log.splitlines()
    command_lines = [l for l in log_lines if l.lstrip().startswith("::")]
    titled, others = [], []
    for line in command_lines:
        parsed = _parse_command(line.lstrip())
        if parsed and parsed[1].get("title") == TITLE:
            titled.append((line, parsed))
        else:
            others.append(line)
    level, start = expect["annotation"]
    if len(titled) != 1:
        errors.append(f"{len(titled)} workflow commands titled '{TITLE}', expected 1")
    else:
        line, (cmd, _, message) = titled[0]
        if line != line.lstrip():
            errors.append("the titled workflow command is indented")
        if cmd != level:
            errors.append(f"titled command level '{cmd}', expected '{level}'")
        if not message.startswith(start):
            errors.append(f"titled message '{message[:60]}', expected start '{start}'")
    for line in others:
        if line not in expect["commands"]:
            errors.append(f"unexpected workflow command: log> {line}")
    for command in expect["commands"]:
        if command_lines.count(command) != 1:
            errors.append(f"expected once, found {command_lines.count(command)} times: "
                          f"log> {command}")

    job = "pass" if all(code in (0, None) for code in results.values()) else "fail"
    if job != expect["job"]:
        errors.append(f"job {job}, expected {expect['job']} (step exits: "
                      + ", ".join(f"{k}={v}" for k, v in results.items()) + ")")

    attempt_line = "Attempt 2 of 2" in summary_text
    if attempt_line != (len(entries) == 2):
        errors.append(f"'Attempt 2 of 2' in summary: {'yes' if attempt_line else 'no'}, "
                      f"with {len(entries)} calls")

    if PR_TEXT_MARKER in log:
        errors.append("PR text reached the log")
    for n in range(1, len(calls) + 1):
        marker = _marker(name, n)
        if marker in log:
            errors.append(f"report text of call {n} reached the log")
        in_summary = marker in summary_text
        if in_summary != (n in expect["in_summary"]):
            errors.append(f"report of call {n} in the summary: {'yes' if in_summary else 'no'}, "
                          f"expected {'yes' if n in expect['in_summary'] else 'no'}")

    shown = titled[0][1] if len(titled) == 1 else None
    desc = (f"{len(entries)} call{'s' if len(entries) != 1 else ''}, "
            + (f"{shown[0]} \"{shown[2][:44]}\"" if shown else f"{len(titled)} titled")
            + (f" + {len(others)} untitled" if others else "")
            + f", job {job}" + (", attempt 2 of 2" if attempt_line else ""))
    return errors, desc, log_lines


def run_extractor_fixture(fixture):
    """`workflow.yml` and `expect` with one `error: <text>` line (the extraction must fail
    with a message containing it) or `error: none` (it must succeed)."""
    want = None
    for line in (fixture / "expect").read_text(encoding="utf-8").splitlines():
        key, _, value = line.partition(": ")
        if key == "error":
            want = value
    if want is None:
        raise ValueError(f"{fixture.name}/expect: no 'error:' line")
    try:
        extract(fixture / "workflow.yml")
        got = None
    except ExtractError as e:
        got = str(e)
    if want == "none":
        return ([] if got is None else [f"extraction failed: {got}"]), "extracted"
    if got is None:
        return [f"extraction succeeded, expected an error containing '{want}'"], ""
    if want not in got:
        return [f"error '{got}', expected it to contain '{want}'"], ""
    return [], f"failed as intended: {got}"


def self_test(script_dir, workflow):
    fixtures = script_dir / "check-pr-review-workflow-fixtures"
    missing = [tool for tool in ("bash", "jq") if shutil.which(tool) is None]
    if missing:
        print(f"check-pr-review-workflow: FAILED, not found on PATH: {', '.join(missing)} "
              "(the scripts under test need them)", file=sys.stderr)
        return 1
    bash = shutil.which("bash")
    version = subprocess.run([bash, "-c", "echo $BASH_VERSION"], capture_output=True,
                             text=True).stdout.strip()

    failed = total = 0
    print(f"--- extractor fixtures ({fixtures.name}/extractor)")
    for fixture in sorted(p for p in (fixtures / "extractor").iterdir() if p.is_dir()):
        total += 1
        errors, desc = run_extractor_fixture(fixture)
        failed += _report(f"extractor/{fixture.name}", errors, desc)

    try:
        extracted = extract(workflow)
    except ExtractError as e:
        print(f"check-pr-review-workflow: FAILED, cannot extract from {workflow}: {e}")
        return 1
    try:
        shown_path = workflow.relative_to(script_dir.parent)
    except ValueError:
        shown_path = workflow
    run_lines = len(extracted["steps"][RUN_STEP]["script"].splitlines())
    map_lines = len(extracted["steps"][MAP_STEP]["script"].splitlines())
    print(f"--- scenarios ({fixtures.name}/scenarios), extracted from {shown_path}: "
          f"'{RUN_STEP}' {run_lines} lines, '{MAP_STEP}' {map_lines} lines, "
          f"REVIEW_MODEL={extracted['env']['REVIEW_MODEL']}, "
          f"REVIEW_MAX_TURNS={extracted['env']['REVIEW_MAX_TURNS']}; run with {bash} -e "
          f"(bash {version})")
    for fixture in sorted(p for p in (fixtures / "scenarios").iterdir() if p.is_dir()):
        total += 1
        try:
            errors, desc, log_lines = run_scenario(fixture, extracted, bash)
        except (OSError, ValueError, KeyError) as e:
            errors, desc, log_lines = [f"fixture error: {e}"], "", []
        failed += _report(f"scenarios/{fixture.name}", errors, desc, log_lines)
    print(f"check-pr-review-workflow self-test: {total - failed}/{total} fixtures passed")
    return 1 if failed or total == 0 else 0


def _report(label, errors, desc, log_lines=()):
    print(f"{'FAIL' if errors else 'ok  '} {label}" + (f": {desc}" if desc else ""))
    if errors:
        print("".join(f"    SELF-TEST FAIL: {e}\n" for e in errors), end="")
        print("".join(f"    log> {line}\n" for line in log_lines), end="")
    return 1 if errors else 0


def main(argv):
    script_dir = Path(__file__).resolve().parent
    workflow = script_dir.parent / ".github" / "workflows" / "pr-review.yml"
    want_self_test = False
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--self-test":
            want_self_test = True
        elif arg == "--workflow" and args:
            workflow = Path(args.pop(0)).resolve()
        else:
            print(f"usage: check-pr-review-workflow.sh --self-test [--workflow <file>] "
                  f"(got '{arg}')", file=sys.stderr)
            return 2
    if not want_self_test:
        print("usage: check-pr-review-workflow.sh --self-test [--workflow <file>]",
              file=sys.stderr)
        return 2
    return self_test(script_dir, workflow)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
