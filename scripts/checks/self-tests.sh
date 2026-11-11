#!/usr/bin/env bash
# Runs and checks the one list of script self-tests, scripts/checks/self-tests.list (format and
# groups in its header). The gate reads the list through --list; CI runs a job's groups through
# --run in one step.
#
#   scripts/checks/self-tests.sh --list <group>...   print `<step name><TAB><script>` per line
#   scripts/checks/self-tests.sh --run <group>...    run each `<script> --self-test`, every one
#                                                    even after a failure; exit 1 if any failed,
#                                                    naming each failed step and its script
#   scripts/checks/self-tests.sh --check             every script with a self-test is listed, and
#                                                    every line is well-formed and names an
#                                                    executable script that has one
#   scripts/checks/self-tests.sh --self-test         the cases in scripts/checks/self-tests-fixtures/
#   --root <dir>   (first) the repository to read (default: this script's checkout; the fixtures)
#
# A script "has a self-test" when it is an executable `*.sh` file under scripts/ (not in a
# `*-fixtures/` directory) whose header documents `scripts/<its own path> --self-test`, or whose
# code tests its first argument against `--self-test`. A `*.py` helper is reached through its
# `.sh` wrapper, so it is never listed itself. scripts/pre-push-check.sh, which runs the
# self-tests, is not a script with one.
# Exit: 0 ok, 1 a failed self-test or check, 2 usage error or unreadable list.
# Bash 3.2 compatible.
set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
USAGE="usage: scripts/checks/self-tests.sh [--root <dir>] (--list <group>... | --run <group>... | --check) | --self-test"
GROUPS_ALLOWED="tooling macos ios-swiftlint"

die() { echo "self-tests: $1" >&2; exit 2; }

list_file() { printf '%s/scripts/checks/self-tests.list\n' "$ROOT"; }

# Lines of the list for the given groups, as `<name><TAB><script>`; exit 2 on a missing file.
list_groups() {
    local f line group name script rest g want
    f="$(list_file)"
    [ -f "$f" ] || die "no list at $f"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in '#'* | '') continue ;; esac
        IFS=$'\t' read -r group name script rest <<< "$line"
        for want in "$@"; do
            if [ "$group" = "$want" ]; then printf '%s\t%s\n' "$name" "$script"; fi
        done
    done < "$f"
    return 0
}

has_self_test() { # <repo-relative path>
    local p="$1"
    [ -f "$ROOT/$p" ] && [ -x "$ROOT/$p" ] || return 1
    grep -qE "^#.*[[:space:]]${p//./\\.}[[:space:]]+--self-test" "$ROOT/$p" && return 0
    grep -vE '^[[:space:]]*#' "$ROOT/$p" | grep -qE '(=|!=)[[:space:]]*"?--self-test"?[[:space:]]*\]|^[[:space:]]*"?--self-test"?\)'
}

check() {
    local f problems=0 line n=0 group name script rest seen="" p
    f="$(list_file)"
    [ -f "$f" ] || die "no list at $f"
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        case "$line" in '#'* | '') continue ;; esac
        IFS=$'\t' read -r group name script rest <<< "$line"
        if [ -z "${script:-}" ] || [ -n "${rest:-}" ] || [ -z "$name" ]; then
            echo "self-tests.list:$n: not <group><TAB><step name><TAB><script>"; problems=$((problems + 1)); continue
        fi
        case " $GROUPS_ALLOWED " in *" $group "*) ;; *)
            echo "self-tests.list:$n: unknown group '$group' (allowed: $GROUPS_ALLOWED)"; problems=$((problems + 1)) ;;
        esac
        case "$seen" in *"|$script|"*)
            echo "self-tests.list:$n: $script is listed twice"; problems=$((problems + 1)) ;;
        esac
        seen="$seen|$script|"
        if ! has_self_test "$script"; then
            echo "self-tests.list:$n: $script is missing, not executable, or has no --self-test"; problems=$((problems + 1))
        fi
    done < "$f"
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        case "$p" in scripts/pre-push-check.sh | *-fixtures/*) continue ;; esac
        has_self_test "$p" || continue
        case "$seen" in *"|$p|"*) ;; *)
            echo "$p has a --self-test but is not in scripts/checks/self-tests.list"; problems=$((problems + 1)) ;;
        esac
    done < <(cd "$ROOT" && find scripts -type f -name '*.sh' | LC_ALL=C sort)
    if [ "$problems" -ne 0 ]; then
        echo "self-tests: check FAILED, $problems problem(s)"
        return 1
    fi
    echo "self-tests: check OK, every script with a self-test is listed"
}

run_groups() {
    local entries name script failed=() total=0
    entries="$(list_groups "$@")" || exit 2
    [ -n "$entries" ] || die "no self-test in group(s): $*"
    while IFS=$'\t' read -r name script; do
        total=$((total + 1))
        echo "==> $name"
        if ! (cd "$ROOT" && "$script" --self-test); then
            failed+=("$name ($script)")
        fi
        echo
    done <<< "$entries"
    if [ "${#failed[@]}" -ne 0 ]; then
        echo "self-tests: ${#failed[@]} of $total FAILED:"
        printf '  %s\n' "${failed[@]}"
        return 1
    fi
    echo "self-tests: all $total passed ($*)"
}

self_test() {
    local fixtures dir name args expect_exit expect out code failed=0
    fixtures="$SELF_DIR/self-tests-fixtures"
    for dir in "$fixtures"/*/; do
        [ -d "$dir" ] || { echo "FAIL no cases in $fixtures"; failed=1; break; }
        name="$(basename "$dir")"
        args="$(cat "$dir/args")"
        expect_exit="$(cat "$dir/expect-exit")"
        # shellcheck disable=SC2086
        out="$(bash "$SELF_DIR/self-tests.sh" --root "$dir/repo" $args 2>&1)"
        code=$?
        if [ "$code" != "$expect_exit" ]; then
            echo "FAIL $name: expected exit $expect_exit, got $code"; printf '%s\n' "$out" | sed 's/^/       /'; failed=1; continue
        fi
        while IFS= read -r expect || [ -n "$expect" ]; do
            [ -n "$expect" ] || continue
            if ! printf '%s\n' "$out" | grep -qF -- "$expect"; then
                echo "FAIL $name: output lacks '$expect'"; printf '%s\n' "$out" | sed 's/^/       /'; failed=1; continue 2
            fi
        done < "$dir/expect"
        echo "ok   $name (exit $code)"
    done
    bash "$SELF_DIR/self-tests.sh" --bogus > /dev/null 2>&1; [ $? = 2 ] || { echo "FAIL a usage error does not exit 2"; failed=1; }
    if [ "$failed" = 0 ]; then echo "self-tests: self-test passed"; else echo "self-tests: self-test FAILED"; fi
    exit "$failed"
}

if [ "${1:-}" = "--self-test" ]; then
    [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }
    self_test
fi
if [ "${1:-}" = "--root" ]; then
    [ "$#" -ge 3 ] || { echo "$USAGE" >&2; exit 2; }
    ROOT="$(cd "$2" 2>/dev/null && pwd)" || die "no such directory: $2"
    shift 2
fi
case "${1:-}" in
    --list)
        shift; [ "$#" -ge 1 ] || { echo "$USAGE" >&2; exit 2; }
        out="$(list_groups "$@")" || exit 2
        [ -n "$out" ] || die "no self-test in group(s): $*"
        printf '%s\n' "$out" ;;
    --run)
        shift; [ "$#" -ge 1 ] || { echo "$USAGE" >&2; exit 2; }
        run_groups "$@" ;;
    --check)
        [ "$#" = 1 ] || { echo "$USAGE" >&2; exit 2; }
        check ;;
    *) echo "$USAGE" >&2; exit 2 ;;
esac
