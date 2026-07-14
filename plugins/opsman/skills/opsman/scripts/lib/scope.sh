# shellcheck shell=sh
# Write-scope helpers. A scoped plan declares its blast radius: the union of
# every step's allowed_files globs. Dirty worktree files must match the
# union. A plan with no allowed_files anywhere is unscoped (no restriction).

# opsman_status <dir> [git-status-flags...] — `git status --porcelain`
# excluding opsman's own control plane: `.opsman/` and the uncommitted
# `.gitignore` edit that hides it. init-run.sh appends `.opsman/` to
# `.gitignore` at start and never commits that edit, so in `branch`/`current`
# mode (where the "workspace" IS the real checkout) anything that discards
# uncommitted state — a stash, a reset, a conflicting checkout — can remove
# it and un-ignore the whole control plane. Every caller that needs a dirty
# read of the real checkout MUST go through this one function rather than
# reimplementing the exclusion pathspec: a caller that copies the pathspec
# by hand is exactly how this bug recurred the first time.
opsman_status() {
  _os_dir=$1
  shift
  git -C "$_os_dir" status --porcelain "$@" -- ':(exclude,literal).gitignore' ':(exclude,literal).opsman/'
}

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
# and `git -C ""` would silently scan the caller's cwd instead. Uses
# opsman_status so opsman's own control plane is never a "violation".
scope_violations() {
  _sv_wt=$1
  _sv_patterns=$(scope_patterns "$2")
  _sv_bl=${3:-}
  [ -n "$_sv_patterns" ] || return 0
  { [ -n "$_sv_wt" ] && [ -d "$_sv_wt" ]; } || return 1
  _sv_status=$(opsman_status "$_sv_wt" --untracked-files=all) || return 1
  [ -n "$_sv_status" ] || return 0
  while IFS= read -r _sv_line; do
    [ -n "$_sv_line" ] || continue
    _sv_path=${_sv_line#???}
    case $_sv_line in
      R* | C*)
        _sv_old=${_sv_path%% -> *}
        _sv_new=${_sv_path##* -> }
        _baseline_has "$_sv_old" "$_sv_bl" \
          || _scope_match "$_sv_old" "$_sv_patterns" || printf '%s\n' "$_sv_old"
        _baseline_has "$_sv_new" "$_sv_bl" \
          || _scope_match "$_sv_new" "$_sv_patterns" || printf '%s\n' "$_sv_new"
        ;;
      *)
        _baseline_has "$_sv_path" "$_sv_bl" \
          || _scope_match "$_sv_path" "$_sv_patterns" || printf '%s\n' "$_sv_path"
        ;;
    esac
  done <<EOF
$_sv_status
EOF
}

# _dirty_paths <dir> — one path per line from git status; renames emit the
# new name (and the old one on its own line, since it changed too). Uses
# opsman_status so opsman's own control plane is never counted as dirt.
_dirty_paths() {
  opsman_status "$1" --untracked-files=all | while IFS= read -r _dp_line; do
    _dp_p=${_dp_line#???}
    case $_dp_line in
      R* | C*)
        printf '%s\n' "${_dp_p%% -> *}"
        printf '%s\n' "${_dp_p##* -> }"
        ;;
      *) printf '%s\n' "$_dp_p" ;;
    esac
  done
}

# baseline_snapshot <dir> <out-file> — record every currently-dirty path
# with a content hash (or "missing"): the pre-existing mess a current-mode
# run must neither count nor touch.
baseline_snapshot() {
  _bs_dir=$1
  _bs_out=$2
  _dirty_paths "$_bs_dir" | LC_ALL=C sort -u | while IFS= read -r _bs_p; do
    [ -n "$_bs_p" ] || continue
    if [ -f "$_bs_dir/$_bs_p" ]; then
      _bs_h=$(sha256_file "$_bs_dir/$_bs_p")
    else
      _bs_h=missing
    fi
    printf '%s\t%s\n' "$_bs_h" "$_bs_p"
  done >"$_bs_out.tmp"
  mv "$_bs_out.tmp" "$_bs_out"
}

# _baseline_has <path> <baseline-file> — 0 when the path is baselined.
_baseline_has() {
  [ -n "$2" ] && [ -f "$2" ] || return 1
  awk -F '\t' -v p="$1" '$2 == p { found = 1 } END { exit !found }' "$2"
}

# baseline_violations <dir> <baseline-file> — baseline paths whose content
# no longer matches the snapshot: the run touched the human's dirty files.
baseline_violations() {
  [ -n "$2" ] && [ -f "$2" ] || return 0
  _bv_tab=$(printf '\t')
  while IFS="$_bv_tab" read -r _bv_h _bv_p; do
    [ -n "$_bv_p" ] || continue
    if [ -f "$1/$_bv_p" ]; then
      _bv_cur=$(sha256_file "$1/$_bv_p")
    else
      _bv_cur=missing
    fi
    [ "$_bv_cur" = "$_bv_h" ] || printf '%s\n' "$_bv_p"
  done <"$2"
}

# snapshot_delta <pre-file> <post-file> — hash\tpath lines from <post-file>
# whose path is missing from, or whose hash differs from, <pre-file>: the
# marginal change between the two snapshots, independent of whatever dirt
# was already present at pre time. Both files are baseline_snapshot's
# hash\tpath format.
snapshot_delta() {
  # FILENAME (not the NR==FNR idiom) distinguishes the two files: NR==FNR
  # misclassifies the second file's first line as still belonging to the
  # first file whenever the first file is empty (both counters start at 1).
  awk -F '\t' -v pref="$1" '
    FILENAME == pref { pre[$2] = $1; next }
    !($2 in pre) || pre[$2] != $1 { print $1 "\t" $2 }
  ' "$1" "$2"
}
