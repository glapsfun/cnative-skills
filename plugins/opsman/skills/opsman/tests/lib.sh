# shellcheck shell=sh
# shellcheck disable=SC2034  # SCRIPTS_DIR is consumed by the sourcing t-*.sh
# Shared helpers for opsman kernel tests. Source from t-*.sh.
set -eu

TESTS_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SCRIPTS_DIR=$TESTS_DIR/../scripts

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

# Isolate from the developer's machine: empty HOME, no extra skill roots.
HOME=$sandbox/home
export HOME
mkdir -p "$HOME"
unset OPSMAN_SKILL_PATH OPSMAN_ROOT OPSMAN_INCLUDE_GLOBAL 2>/dev/null || true

mkrepo() {
  _r=$sandbox/repo
  mkdir -p "$_r"
  git -C "$_r" init -q
  git -C "$_r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  printf '%s\n' "$_r"
}

mkskill() { # dir name description — SKILL.md fixture matching the discoverer contract
  mkdir -p "$1"
  printf -- '---\nname: %s\ndescription: %s\n---\n\nbody\n' "$2" "$3" >"$1/SKILL.md"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() { # actual expected [label]
  [ "$1" = "$2" ] || fail "expected [$2], got [$1] ${3:-}"
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_status() { # expected_code cmd [args...]
  _want=$1
  shift
  set +e
  "$@" >/dev/null 2>&1
  _got=$?
  set -e
  [ "$_got" -eq "$_want" ] || fail "expected exit $_want, got $_got: $*"
}

# Drive a NEW run to IMPLEMENTING with one command-backed plan step (s1) and
# one acceptance check (c1). cwd must be the fixture repo root. Extra args
# (e.g. --limit max_iterations=2) pass through to init-run.sh.
# Sets globals: run_id, rd.
run_to_implementing() {
  mkskill ".claude/skills/probe" probe "probe fixture skill"
  "$SCRIPTS_DIR/build-registry.sh"
  run_id=$("$SCRIPTS_DIR/init-run.sh" "$@" "drive probe task" | tail -n 1)
  rd=$(pwd)/.opsman/runs/$run_id
  "$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsIndexed
  "$SCRIPTS_DIR/classify.sh" --run "$run_id"
  jq '.keywords = ["probe"] | .domain = "dev" | .risk = "low"
      | .acceptance_criteria = ["probe check passes"]' \
    "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
  mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
  "$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TaskClassified
  "$SCRIPTS_DIR/select-skills.sh" --run "$run_id"
  jq -n '{selected: [{skill: "probe", role: "primary", reason: "fixture"}]}' \
    >"$rd/selected-skills.yaml"
  "$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsSelected
  jq -n '{steps: [{id: "s1", uses: "probe", depends_on: [], risk: "R1", success: "ok",
                   command: "printf done > out.txt", cwd: "."}]}' >"$rd/plan.yaml"
  "$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event PlanCreated
  jq -n '{checks: [{id: "c1", command: "test -f out.txt", expected_exit: 0}]}' \
    >"$rd/acceptance.yaml"
  "$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TestsDefined
  "$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event BaselineRecorded
  "$SCRIPTS_DIR/create-worktree.sh" --run "$run_id" >/dev/null
}

# Continue a run_to_implementing run to JUDGING (execute step, validate).
run_to_judging() {
  "$SCRIPTS_DIR/run-step.sh" --run "$run_id" s1 >/dev/null
  "$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event ImplementationCompleted
  "$SCRIPTS_DIR/run-tests.sh" --run "$run_id" >/dev/null
  "$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event ValidationCompleted
}
