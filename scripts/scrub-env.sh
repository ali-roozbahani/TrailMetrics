#!/usr/bin/env bash
# Removes secret-looking variables from the environment of the shell that sources this file, so
# that nothing it starts afterwards inherits them. scripts/pre-push-check.sh sources it at its
# start: xcodebuild logs the environment of the scheme pre-action and of the Run Script phase,
# and the gate needs no token, so the gate does not keep any.
#
#   source scripts/scrub-env.sh      defines scrub_secret_env and runs nothing
#   scripts/scrub-env.sh --self-test runs the self-test below (fake values only); exit 0 = all ok
#   anything else                    prints the usage line and exits 2
#
# scrub_secret_env unsets every exported variable whose NAME matches the deny list below
# (shell `case` patterns, case-sensitive) and prints one line with the number and the names of
# the removed variables, never a value. Names come from `compgen -e`, which lists names only and
# is not confused by a value that contains a newline. A matching name that bash cannot unset (a
# readonly variable, or a name that is not a valid shell identifier, such as `A.TOKEN`, which
# bash 3.2 imports but cannot unset) is named on stderr and the function returns 1, so a caller
# can stop instead of running with it. Variables that are set but not exported are left alone.
#
# The patterns match anywhere they say: `*TOKEN*` also removes a name like `TOKENIZER_OK`, and
# `CLAUDE*` also removes `CLAUDEX`. That is intended (a false positive costs nothing in the
# gate); the self-test pins it. Tool locations (PATH, HOME, JAVA_HOME, ANDROID_*, DEVELOPER_DIR,
# TMPDIR, LANG, LC_*) match no pattern. Do not add broad patterns such as `*KEY*`.
#
# bash 3.2 compatible (macOS /bin/bash): no associative arrays, no ${var,,}, no mapfile.

scrub_secret_env() {
    local _tm_scrub_name _tm_scrub_count=0 _tm_scrub_removed="" _tm_scrub_failed=""
    while IFS= read -r _tm_scrub_name; do
        case "$_tm_scrub_name" in
            *TOKEN*|*SECRET*|*PASSWORD*|*PASSWD*|*CREDENTIAL*|*API_KEY*|*APIKEY*|*PRIVATE_KEY*|*ACCESS_KEY*|ANTHROPIC_*|CLAUDE*|GH_*|GITHUB_*) ;;
            *) continue ;;
        esac
        if unset -v "$_tm_scrub_name" 2>/dev/null; then
            _tm_scrub_count=$((_tm_scrub_count + 1))
            _tm_scrub_removed="$_tm_scrub_removed $_tm_scrub_name"
        else
            _tm_scrub_failed="$_tm_scrub_failed $_tm_scrub_name"
        fi
    done <<EOF
$(compgen -e)
EOF
    echo "scrub-env: removed $_tm_scrub_count secret-looking variable(s) from the environment:${_tm_scrub_removed:- none}"
    if [ -n "$_tm_scrub_failed" ]; then
        echo "scrub-env: FAILED, could not remove (readonly, or not a valid shell name):$_tm_scrub_failed" >&2
        return 1
    fi
    return 0
}

# Sourced: stop here, so the caller gets scrub_secret_env and nothing else.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    return 0
fi

# --- Self-test (only when executed with --self-test) --------------------------------------------
# Every case starts a fresh bash under `env -i` with a fixed PATH and HOME plus the case's fake
# variables, so the real environment never enters it. The child sources this file (the copy being
# tested, so a mutated copy tests itself), prints the exported NAMES before and after
# scrub_secret_env, the function's line and its return code. Values are only ever fake
# (`fake-value-N` for names that must go, `keep-value-N` for names that must stay).

ST_PASS=0
ST_FAIL=0
ST_OUT=""
ST_RC=0

# The child: $1 = the file to source, $2 = mode.
# shellcheck disable=SC2016
ST_CHILD='
set -u
. "$1" || { echo "child-error: source failed"; exit 3; }
mode="$2"
st_names() { while IFS= read -r n; do [ -n "$n" ] && echo "$1:$n"; done <<EOF
$(compgen -e)
EOF
}
st_names before
case "$mode" in
    source-only) st_names after; exit 0 ;;
    unexported) TM_LOCAL_TOKEN=fake-value-local ;;
    readonly) declare -r TM_FAKE_RO_TOKEN ;;
esac
scrub_secret_env
echo "rc:$?"
if [ "$mode" = twice ]; then
    scrub_secret_env
    echo "rc2:$?"
fi
if [ "$mode" = unexported ]; then
    if [ "${TM_LOCAL_TOKEN-}" = fake-value-local ]; then echo "unexported:kept"; else echo "unexported:gone"; fi
fi
st_names after
'

# st_run <mode> [NAME=VALUE ...]: runs the child; output in ST_OUT, exit code in ST_RC.
st_run() {
    local mode="$1"
    shift
    ST_OUT="$(env -i PATH=/usr/bin:/bin HOME=/tm-fake-home "$@" "$ST_BASH" -c "$ST_CHILD" scrub-child "$ST_SELF" "$mode" 2>&1)"
    ST_RC=$?
}

st_has() { printf '%s\n' "$ST_OUT" | grep -qxF -- "$1"; }

# The first scrub line's list of names, with a space on each side.
st_removed_list() {
    local line
    line="$(printf '%s\n' "$ST_OUT" | grep -m1 '^scrub-env: removed ')"
    echo " ${line#*environment:} "
}

st_count_of_first_line() {
    printf '%s\n' "$ST_OUT" | grep -m1 '^scrub-env: removed ' | sed 's/^scrub-env: removed \([0-9]*\) .*/\1/'
}

# st_expect_removed <name>...: each name was exported before, is gone after and is on the line.
ST_PROBLEMS=""
st_expect_removed() {
    local name list
    list="$(st_removed_list)"
    for name in "$@"; do
        st_has "before:$name" || ST_PROBLEMS="$ST_PROBLEMS; precondition: $name not exported in the child"
        st_has "after:$name" && ST_PROBLEMS="$ST_PROBLEMS; $name still exported"
        case "$list" in *" $name "*) ;; *) ST_PROBLEMS="$ST_PROBLEMS; $name not on the removal line" ;; esac
    done
}

# st_expect_kept <name>...: each name was exported before and still is after.
st_expect_kept() {
    local name
    for name in "$@"; do
        st_has "before:$name" || ST_PROBLEMS="$ST_PROBLEMS; precondition: $name not exported in the child"
        st_has "after:$name" || ST_PROBLEMS="$ST_PROBLEMS; $name was removed"
    done
}

st_expect() { st_has "$1" || ST_PROBLEMS="$ST_PROBLEMS; expected '$1'"; }

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
        echo "scrub-env self-test: FAILED, precondition: no executable \$BASH" >&2
        return 1
    fi
    if ! command -v env >/dev/null 2>&1 || ! type compgen >/dev/null 2>&1; then
        echo "scrub-env self-test: FAILED, precondition: env or compgen not available" >&2
        return 1
    fi
    if [ ! -r "$ST_SELF" ]; then
        echo "scrub-env self-test: FAILED, precondition: cannot read $ST_SELF" >&2
        return 1
    fi
    echo "scrub-env self-test: $ST_SELF with $ST_BASH (bash $("$ST_BASH" -c 'echo "$BASH_VERSION"'))"

    # One case per deny-list pattern; each name matches that pattern and no other.
    local pattern name n=0
    while read -r pattern name; do
        n=$((n + 1))
        st_run once "$name=fake-value-$n"
        st_expect "rc:0"
        st_expect_removed "$name"
        st_result "pattern $pattern removes $name"
    done <<'EOF'
*TOKEN* TM_FAKE_SESSION_TOKEN
*SECRET* TM_FAKE_SECRET_VALUE
*PASSWORD* TM_FAKE_DB_PASSWORD
*PASSWD* TM_FAKE_PASSWD
*CREDENTIAL* TM_FAKE_CREDENTIALS_FILE
*API_KEY* TM_FAKE_API_KEY
*APIKEY* TM_FAKE_APIKEY
*PRIVATE_KEY* TM_FAKE_PRIVATE_KEY
*ACCESS_KEY* TM_FAKE_ACCESS_KEY_ID
ANTHROPIC_* ANTHROPIC_TM_FAKE_MODEL
CLAUDE* CLAUDE_TM_FAKE_ENTRYPOINT
GH_* GH_TM_FAKE_HOST
GITHUB_* GITHUB_TM_FAKE_REPOSITORY
EOF

    # Names matching several patterns go too.
    st_run once TM_FAKE_SECRET_TOKEN=fake-value-20 TM_FAKE_ANTHROPIC_API_KEY=fake-value-21 TM_FAKE_GH_TOKEN=fake-value-22
    st_expect "rc:0"
    st_expect_removed TM_FAKE_SECRET_TOKEN TM_FAKE_ANTHROPIC_API_KEY TM_FAKE_GH_TOKEN
    [ "$(st_count_of_first_line)" = 3 ] || ST_PROBLEMS="$ST_PROBLEMS; count is not 3"
    st_result "names matching several patterns are removed, count 3"

    # Tool locations and near misses stay. The patterns are case-sensitive and the prefix
    # patterns (ANTHROPIC_*, GH_*, GITHUB_*) are anchored at the start of the name.
    st_run once JAVA_HOME=/fake/jdk ANDROID_HOME=/fake/sdk DEVELOPER_DIR=/fake/xcode \
        TMPDIR=/fake/tmp LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 USER=tm-fake-user SHELL=/bin/bash \
        TM_KEEP_ME=keep-value-1 MONKEY=keep-value-2 MY_ANTHROPIC_URL=keep-value-3 \
        XGH_HOST=keep-value-4 GITHUBX=keep-value-5 tm_fake_token_lowercase=keep-value-6
    st_expect "rc:0"
    st_expect_kept PATH HOME JAVA_HOME ANDROID_HOME DEVELOPER_DIR TMPDIR LANG LC_ALL USER SHELL \
        TM_KEEP_ME MONKEY MY_ANTHROPIC_URL XGH_HOST GITHUBX tm_fake_token_lowercase
    [ "$(st_count_of_first_line)" = 0 ] || ST_PROBLEMS="$ST_PROBLEMS; count is not 0"
    st_result "tool locations and near misses are kept"

    # TOKENIZER_OK contains TOKEN, so *TOKEN* removes it. Pinned on purpose, not hidden.
    st_run once TOKENIZER_OK=fake-value-30
    st_expect "rc:0"
    st_expect_removed TOKENIZER_OK
    st_result "TOKENIZER_OK matches *TOKEN* and is removed"

    # A value with a newline: the variable still goes, a kept one with a newline stays, and no
    # line of the value is taken for a name.
    st_run once "TM_FAKE_MULTILINE_TOKEN=fake-value-40
NOT_A_NAME_TOKEN=fake-value-41" "TM_KEEP_MULTILINE=keep-value-42
keep-value-43"
    st_expect "rc:0"
    st_expect_removed TM_FAKE_MULTILINE_TOKEN
    st_expect_kept TM_KEEP_MULTILINE
    st_has "before:NOT_A_NAME_TOKEN" && ST_PROBLEMS="$ST_PROBLEMS; a value line was listed as a name"
    [ "$(st_count_of_first_line)" = 1 ] || ST_PROBLEMS="$ST_PROBLEMS; count is not 1"
    st_result "a value with a newline is removed and nothing breaks"

    # Set but not exported: left alone (it never reaches a child process anyway).
    st_run unexported
    st_expect "rc:0"
    st_expect "unexported:kept"
    st_result "a variable that is set but not exported is left alone"

    # The line names the variables and the count, never a value.
    local args=() i=50
    for name in TM_FAKE_SESSION_TOKEN TM_FAKE_SECRET_VALUE TM_FAKE_DB_PASSWORD TM_FAKE_PASSWD \
        TM_FAKE_CREDENTIALS_FILE TM_FAKE_API_KEY TM_FAKE_APIKEY TM_FAKE_PRIVATE_KEY \
        TM_FAKE_ACCESS_KEY_ID ANTHROPIC_TM_FAKE_MODEL CLAUDE_TM_FAKE_ENTRYPOINT GH_TM_FAKE_HOST \
        GITHUB_TM_FAKE_REPOSITORY; do
        args+=("$name=fake-value-$i")
        i=$((i + 1))
    done
    st_run once "${args[@]}"
    st_expect "rc:0"
    [ "$(st_count_of_first_line)" = 13 ] || ST_PROBLEMS="$ST_PROBLEMS; count is not 13"
    case "$ST_OUT" in *fake-value*) ST_PROBLEMS="$ST_PROBLEMS; output contains a fake value" ;; esac
    st_result "the removal line prints names and count, never a value"

    # Twice: the second call removes nothing and prints 0.
    st_run twice TM_FAKE_SESSION_TOKEN=fake-value-70
    st_expect "rc:0"
    st_expect "rc2:0"
    st_expect_removed TM_FAKE_SESSION_TOKEN
    st_expect "scrub-env: removed 0 secret-looking variable(s) from the environment: none"
    st_result "a second call removes nothing and prints 0"

    # Fail closed: a matching name bash cannot unset makes the function return 1 and is named.
    st_run readonly TM_FAKE_RO_TOKEN=fake-value-80
    st_expect "rc:1"
    st_expect "scrub-env: FAILED, could not remove (readonly, or not a valid shell name): TM_FAKE_RO_TOKEN"
    st_result "a readonly matching variable fails closed"

    st_run once "TM.FAKE_TOKEN=fake-value-81"
    st_expect "rc:1"
    st_expect "scrub-env: FAILED, could not remove (readonly, or not a valid shell name): TM.FAKE_TOKEN"
    st_result "a matching name that is not a valid identifier fails closed"

    # Sourcing defines the function and runs nothing.
    st_run source-only TM_FAKE_SESSION_TOKEN=fake-value-90
    st_expect_kept TM_FAKE_SESSION_TOKEN
    case "$ST_OUT" in *scrub-env:*) ST_PROBLEMS="$ST_PROBLEMS; sourcing printed a scrub line" ;; esac
    st_result "sourcing the file runs nothing"

    # Executed without arguments or with an unknown one: usage line, exit 2.
    local usage_arg
    for usage_arg in "" --unknown; do
        ST_OUT="$(env -i PATH=/usr/bin:/bin "$ST_BASH" "$ST_SELF" $usage_arg 2>&1)"
        ST_RC=$?
        [ "$ST_RC" = 2 ] || ST_PROBLEMS="$ST_PROBLEMS; exit code $ST_RC, expected 2"
        case "$ST_OUT" in usage:*) ;; *) ST_PROBLEMS="$ST_PROBLEMS; no usage line" ;; esac
        st_result "executed with '${usage_arg:-no arguments}' prints usage and exits 2"
    done

    echo "scrub-env self-test: $ST_PASS passed, $ST_FAIL failed"
    [ "$ST_FAIL" -eq 0 ] && [ "$ST_PASS" -gt 0 ]
}

set -u
if [ $# -eq 1 ] && [ "$1" = --self-test ]; then
    self_test
    exit $?
fi
echo "usage: source scripts/scrub-env.sh (then call scrub_secret_env) | scripts/scrub-env.sh --self-test" >&2
exit 2
