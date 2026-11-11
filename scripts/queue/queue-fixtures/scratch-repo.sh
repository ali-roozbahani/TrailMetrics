# Sourced by the self-tests of scripts/queue/merge-only-check.sh and local-verdict-for-head.sh:
# helpers that build branch histories in a scratch repository $r (no network, no remote; the ref
# refs/remotes/origin/main follows the local main). Files are 20 numbered lines.
g() { git -C "$r" "$@"; }
lines20() { local i; for i in $(seq 1 20); do echo "line $i"; done; }
sync_main() { g update-ref refs/remotes/origin/main "$(g rev-parse main)"; }
scratch_repo() { # scratch_repo <dir>
    r="$1"
    git init -q -b main "$r"
    g config user.email t@example.com; g config user.name t; g config commit.gpgsign false
    lines20 > "$r/f1"; lines20 > "$r/f2"
    g add f1 f2; g commit -q -m base; g branch base
    sync_main
}
co() { g switch -q "$1"; }
br() { g switch -q -c "$1" "$2"; }                  # br <new branch> <from>
edit() { # edit <file> <line> <text>: on the current branch, one commit (the branch name is in the
    # message: the same edit on two branches in the same second must not make the same commit)
    [ -f "$r/$1" ] || lines20 > "$r/$1"
    awk -v n="$2" -v t="$3" 'NR == n { print t; next } { print }' "$r/$1" > "$r/$1.tmp" && mv "$r/$1.tmp" "$r/$1"
    g add "$1"; g commit -q -m "$(g branch --show-current): edit $1:$2"
}
main_commit() { co main; lines20 > "$r/$1"; g add "$1"; g commit -q -m "$2"; sync_main; }   # a new file on main
main_edit() { co main; edit "$1" "$2" "$3"; sync_main; }
squash() { co main; g merge -q --squash "$1" >/dev/null 2>&1; g commit -q -m "squash $1"; sync_main; }
gm() { co "$1"; g merge -q --no-ff -m "$2" main >/dev/null; }   # gm <branch> <message>: merge main into it
