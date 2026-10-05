#!/usr/bin/env bash
# Filters xcodebuild output so that the gate does not print Xcode's environment dumps.
# Xcode passes its build settings (a Maps key among them) to the scheme pre-action and to Run
# Script phases and logs them as `    export NAME\=value` lines; scripts/scrub-env.sh cannot
# remove build settings, because they are not in the gate's environment. scripts/pre-push-check.sh
# pipes both of its xcodebuild commands through this script.
#
#   scripts/filter-xcode-log.sh              copies standard input to standard output without
#                                            the dump lines; exit code is sed's (0 = ok)
#   scripts/filter-xcode-log.sh --self-test  runs the self-test below (fake values only); exit 0 = all ok
#   anything else                            prints the usage line and exits 2
#
# A dump line starts with whitespace, then the whole word `export` or `setenv`, then whitespace.
# Everything else passes unchanged, in order: `    exporting symbols`, `    export_dir=/x`, a
# line with `export` later in the text, and an `export` at the very start of a line (no leading
# whitespace, which is not Xcode's dump shape). The filter works on lines, not on secrets: a value
# that contains a newline leaks its later lines, and a secret printed in any other shape passes.
#
# Line by line (`sed -u`), so the gate's output still appears while the build runs. `LC_ALL=C`, so
# a byte that is not valid UTF-8 cannot make BSD sed fail. bash 3.2 and BSD sed compatible; `-u`
# exists in both BSD and GNU sed.

TM_XCODE_EXPORT_LINE='/^[[:space:]]+export[[:space:]]/d'
TM_XCODE_SETENV_LINE='/^[[:space:]]+setenv[[:space:]]/d'

filter_xcode_log() {
    LC_ALL=C sed -u -E -e "$TM_XCODE_EXPORT_LINE" -e "$TM_XCODE_SETENV_LINE"
}

# --- Self-test (only when executed with --self-test) --------------------------------------------
# Every case runs this file (the copy being tested, so a mutated copy tests itself) as a filter
# over a fake input in a scratch directory and checks its output and exit code. Values are only
# ever fake: `fake-value-N` on lines that must be dropped, `keep-value-N` on lines that must stay.
# A case reports what went wrong by name, never by printing the filter's output.

ST_PASS=0
ST_FAIL=0
ST_RC=0
ST_PROBLEMS=""

# st_filter <input file> [VAR=VALUE ...]: filters the input; output in $ST_DIR/out, stderr in
# $ST_DIR/err, exit code in ST_RC. Extra arguments go to `env` (for the locale cases).
st_filter() {
    local input="$1"
    shift
    env "$@" "$ST_BASH" "$ST_SELF" <"$input" >"$ST_DIR/out" 2>"$ST_DIR/err"
    ST_RC=$?
}

# st_input <printf format> [args]: writes the case's input to $ST_DIR/in.
st_input() {
    # shellcheck disable=SC2059
    printf "$@" >"$ST_DIR/in"
}

st_expect_rc0() {
    [ "$ST_RC" = 0 ] || ST_PROBLEMS="$ST_PROBLEMS; exit code $ST_RC, expected 0"
    [ -s "$ST_DIR/err" ] && ST_PROBLEMS="$ST_PROBLEMS; the filter wrote to stderr"
}

# st_expect_output <printf format> [args]: the output is exactly these bytes.
st_expect_output() {
    # shellcheck disable=SC2059
    printf "$@" >"$ST_DIR/expected"
    cmp -s "$ST_DIR/expected" "$ST_DIR/out" || ST_PROBLEMS="$ST_PROBLEMS; output differs from the expected lines"
}

st_expect_no_fake_value() {
    [ "$(LC_ALL=C grep -c 'fake-value' "$ST_DIR/out")" = 0 ] || ST_PROBLEMS="$ST_PROBLEMS; output contains a fake-value"
}

st_result() {
    if [ -z "$ST_PROBLEMS" ]; then
        echo "ok   $1"
        ST_PASS=$((ST_PASS + 1))
    else
        echo "FAIL $1:${ST_PROBLEMS#;}"
        ST_FAIL=$((ST_FAIL + 1))
    fi
    ST_PROBLEMS=""
}

self_test() {
    ST_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    ST_BASH="${BASH:-}"
    # Preconditions: fail loudly, never skip.
    if [ -z "$ST_BASH" ] || [ ! -x "$ST_BASH" ]; then
        echo "filter-xcode-log self-test: FAILED, precondition: no executable \$BASH" >&2
        return 1
    fi
    local tool
    for tool in sed mktemp env cmp grep date; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "filter-xcode-log self-test: FAILED, precondition: $tool not available" >&2
            return 1
        fi
    done
    if [ ! -r "$ST_SELF" ]; then
        echo "filter-xcode-log self-test: FAILED, precondition: cannot read $ST_SELF" >&2
        return 1
    fi
    ST_DIR="$(mktemp -d 2>/dev/null)"
    if [ -z "$ST_DIR" ] || [ ! -d "$ST_DIR" ]; then
        echo "filter-xcode-log self-test: FAILED, precondition: mktemp -d failed" >&2
        return 1
    fi
    trap 'rm -rf "$ST_DIR"' EXIT
    echo "filter-xcode-log self-test: $ST_SELF with $ST_BASH (bash $("$ST_BASH" -c 'echo "$BASH_VERSION"'))"

    # Xcode's exact shape: four spaces, `export `, name, backslash, `=`, value.
    st_input '    export TM_FAKE_BUILD_SETTING\\=fake-value-1\n'
    st_filter "$ST_DIR/in"
    st_expect_rc0
    st_expect_output ''
    st_result "an Xcode export line (four spaces, export NAME\\=value) is dropped"

    st_input '    setenv TM_FAKE_BUILD_SETTING fake-value-2\n'
    st_filter "$ST_DIR/in"
    st_expect_rc0
    st_expect_output ''
    st_result "a setenv line is dropped"

    st_input '\texport TM_FAKE_BUILD_SETTING\\=fake-value-3\n'
    st_filter "$ST_DIR/in"
    st_expect_rc0
    st_expect_output ''
    st_result "an export line indented with a tab is dropped"

    # The whole word only: these lines stay, byte for byte.
    st_input '    exporting symbols keep-value-4\n    export_dir=/tm-fake/keep-value-5\n    note: TM_FAKE_TOOL will export keep-value-6\n    setenv_dir=/tm-fake/keep-value-7\n'
    st_filter "$ST_DIR/in"
    st_expect_rc0
    st_expect_output '    exporting symbols keep-value-4\n    export_dir=/tm-fake/keep-value-5\n    note: TM_FAKE_TOOL will export keep-value-6\n    setenv_dir=/tm-fake/keep-value-7\n'
    st_result "exporting, export_dir=, setenv_dir= and export later in the line stay"

    st_input 'CompileSwift normal arm64 /tm-fake/View.swift\n    export TM_FAKE_BUILD_SETTING\\=fake-value-8\n** BUILD SUCCEEDED **\n    setenv TM_FAKE_OTHER fake-value-9\n/tm-fake/View.swift:1:1: error: tm fake error\n'
    st_filter "$ST_DIR/in"
    st_expect_rc0
    st_expect_output 'CompileSwift normal arm64 /tm-fake/View.swift\n** BUILD SUCCEEDED **\n/tm-fake/View.swift:1:1: error: tm fake error\n'
    st_result "compiler, BUILD SUCCEEDED and error lines stay in order"

    : >"$ST_DIR/in"
    st_filter "$ST_DIR/in"
    st_expect_rc0
    st_expect_output ''
    st_result "empty input gives empty output and exit 0"

    # A byte that is not valid UTF-8 (0xff), under a UTF-8 locale as the gate's shell usually has:
    # the kept line passes byte for byte, the dump line with such a byte is still dropped.
    st_input 'Ld /tm-fake/keep-value-10 \377 byte\n    export TM_FAKE_BUILD_SETTING\\=fake-value-11\377\n'
    st_filter "$ST_DIR/in" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
    st_expect_rc0
    st_expect_output 'Ld /tm-fake/keep-value-10 \377 byte\n'
    st_result "a line with an invalid UTF-8 byte passes and the filter does not fail"

    st_input 'first keep-value-12\nlast keep-value-13 without newline'
    st_filter "$ST_DIR/in"
    st_expect_rc0
    LC_ALL=C grep -qxF 'last keep-value-13 without newline' "$ST_DIR/out" \
        || ST_PROBLEMS="$ST_PROBLEMS; the last line without a newline is missing"
    st_result "input without a trailing newline keeps its last line"

    # A sample log: nothing from a dropped line reaches the output, every other line does.
    st_input '%s\n' \
        'Build settings from command line:' \
        '    ARCHS = arm64' \
        'PhaseScriptExecution Build\ KMP\ Shared\ Framework /tm-fake/Script.sh (in target '"'"'TrailMetrics'"'"')' \
        '    cd /tm-fake/iosApp' \
        '    export TM_FAKE_BUILD_SETTING\=fake-value-20' \
        '    export TM_FAKE_INFOPLIST_KEY\=fake-value-21' \
        '    export TM_FAKE_PATH\=/tm-fake/bin:fake-value-22' \
        '    setenv TM_FAKE_LEGACY fake-value-23' \
        '	export TM_FAKE_TABBED\=fake-value-24' \
        '    /bin/sh -c /tm-fake/Script.sh' \
        'Build KMP Shared Framework: up to date, skipping Gradle build keep-value-25' \
        '** BUILD SUCCEEDED **'
    st_filter "$ST_DIR/in"
    st_expect_rc0
    st_expect_no_fake_value
    [ "$(LC_ALL=C grep -c '' "$ST_DIR/out")" = 7 ] || ST_PROBLEMS="$ST_PROBLEMS; expected 7 kept lines"
    LC_ALL=C grep -qxF '** BUILD SUCCEEDED **' "$ST_DIR/out" || ST_PROBLEMS="$ST_PROBLEMS; BUILD SUCCEEDED line missing"
    st_result "a sample log keeps 7 lines and no fake-value from a dropped line"

    # Line by line: the first line comes out while the input is still open. A filter that buffers
    # its output until the end would deliver it only after the producer's 3 second pause.
    local start first_at
    start="$(date +%s)"
    first_at="$({ printf 'Compile keep-value-30\n'; sleep 3; printf 'Link keep-value-31\n'; } \
        | "$ST_BASH" "$ST_SELF" 2>/dev/null \
        | { IFS= read -r _line; date +%s; cat >/dev/null; })"
    [ -n "$first_at" ] && [ $((first_at - start)) -le 1 ] \
        || ST_PROBLEMS="$ST_PROBLEMS; the first line came out only after $((${first_at:-0} - start)) s"
    st_result "output is written line by line while the input is still open"

    # Executed with an unknown argument: usage line on stderr, exit 2, no filtering.
    local usage_arg
    for usage_arg in --unknown -x; do
        printf 'keep-value-40\n' | "$ST_BASH" "$ST_SELF" "$usage_arg" >"$ST_DIR/out" 2>"$ST_DIR/err"
        ST_RC=$?
        [ "$ST_RC" = 2 ] || ST_PROBLEMS="$ST_PROBLEMS; exit code $ST_RC, expected 2"
        LC_ALL=C grep -q '^usage:' "$ST_DIR/err" || ST_PROBLEMS="$ST_PROBLEMS; no usage line"
        [ -s "$ST_DIR/out" ] && ST_PROBLEMS="$ST_PROBLEMS; wrote to stdout"
        st_result "executed with '$usage_arg' prints usage and exits 2"
    done

    echo "filter-xcode-log self-test: $ST_PASS passed, $ST_FAIL failed"
    [ "$ST_FAIL" -eq 0 ] && [ "$ST_PASS" -gt 0 ]
}

set -u
if [ $# -eq 0 ]; then
    filter_xcode_log
    exit $?
fi
if [ $# -eq 1 ] && [ "$1" = --self-test ]; then
    self_test
    exit $?
fi
echo "usage: scripts/filter-xcode-log.sh < xcodebuild-output | scripts/filter-xcode-log.sh --self-test" >&2
exit 2
