# shellcheck shell=sh
# Write-scope helpers. A scoped plan declares its blast radius: the union of
# every step's allowed_files globs. Dirty worktree files must match the
# union. A plan with no allowed_files anywhere is unscoped (no restriction).

# scope_patterns <plan-file> — union of allowed_files, one pattern per line.
# Empty output means unscoped. A missing plan file behaves as unscoped.
scope_patterns() {
  [ -f "$1" ] || return 0
  jq -r '.steps[].allowed_files[]?' "$1"
}

# _scope_match <path> <patterns> — 0 if path matches any glob in the
# newline-separated patterns list. case patterns let * cross /, so src/*
# covers the whole subtree.
_scope_match() {
  _sm_path=$1
  _sm_rc=1
  while IFS= read -r _sm_pat; do
    [ -n "$_sm_pat" ] || continue
    # shellcheck disable=SC2254  # unquoted on purpose: glob match
    case $_sm_path in
      $_sm_pat) _sm_rc=0 ;;
    esac
  done <<EOF
$2
EOF
  return "$_sm_rc"
}

# scope_violations <worktree-dir> <plan-file> — dirty files outside the
# union, one per line; no output means clean or unscoped. Paths that git
# C-quotes (spaces, special characters) will not match a plain glob and are
# reported — fail closed. A missing worktree or failing git also fails
# closed (nonzero): an unverifiable tree must never pass a scoped gate,
# and `git -C ""` would silently scan the caller's cwd instead.
scope_violations() {
  _sv_wt=$1
  _sv_patterns=$(scope_patterns "$2")
  [ -n "$_sv_patterns" ] || return 0
  { [ -n "$_sv_wt" ] && [ -d "$_sv_wt" ]; } || return 1
  _sv_status=$(git -C "$_sv_wt" status --porcelain --untracked-files=all) || return 1
  [ -n "$_sv_status" ] || return 0
  while IFS= read -r _sv_line; do
    [ -n "$_sv_line" ] || continue
    _sv_path=${_sv_line#???}
    case $_sv_line in
      R* | C*)
        _sv_old=${_sv_path%% -> *}
        _sv_new=${_sv_path##* -> }
        _scope_match "$_sv_old" "$_sv_patterns" || printf '%s\n' "$_sv_old"
        _scope_match "$_sv_new" "$_sv_patterns" || printf '%s\n' "$_sv_new"
        ;;
      *)
        _scope_match "$_sv_path" "$_sv_patterns" || printf '%s\n' "$_sv_path"
        ;;
    esac
  done <<EOF
$_sv_status
EOF
}
