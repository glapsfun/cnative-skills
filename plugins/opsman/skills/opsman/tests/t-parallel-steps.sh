#!/bin/sh
# shellcheck disable=SC1091,SC2154  # lib.sh is sourced at runtime; it defines the vars
# shellcheck disable=SC2034  # OPSMAN_ROOT/OPSMAN_STEP_WORKTREES_DIR are consumed by lib/parallel.sh
# Parallel plan-step execution: ready-steps, step-run, step-land.
. "$(dirname -- "$0")/lib.sh"

# --- unit: lib/scope.sh snapshot_delta --------------------------------------
. "$SCRIPTS_DIR/lib/common.sh"
. "$SCRIPTS_DIR/lib/scope.sh"

pre=$sandbox/pre.tsv
post=$sandbox/post.tsv

# unchanged path: no delta
printf 'aaa\tsame.txt\n' >"$pre"
printf 'aaa\tsame.txt\n' >"$post"
assert_eq "$(snapshot_delta "$pre" "$post")" "" "unchanged path produces no delta"

# modified path: reported
printf 'aaa\tchanged.txt\n' >"$pre"
printf 'bbb\tchanged.txt\n' >"$post"
assert_eq "$(snapshot_delta "$pre" "$post")" "$(printf 'bbb\tchanged.txt')" "modified path is delta"

# new path (absent from pre): reported
: >"$pre"
printf 'ccc\tnew.txt\n' >"$post"
assert_eq "$(snapshot_delta "$pre" "$post")" "$(printf 'ccc\tnew.txt')" "new path is delta"

# mix of changed, new, and unchanged
printf 'aaa\tsame.txt\nbbb\told.txt\n' >"$pre"
printf 'aaa\tsame.txt\nzzz\told.txt\nccc\tnew.txt\n' >"$post"
want=$(printf 'zzz\told.txt\nccc\tnew.txt')
assert_eq "$(snapshot_delta "$pre" "$post")" "$want" "mixed snapshot reports only changed/new paths"

# --- unit: lib/parallel.sh ----------------------------------------------
. "$SCRIPTS_DIR/lib/paths.sh"
. "$SCRIPTS_DIR/lib/parallel.sh"

repo=$(mkrepo)
cd "$repo" || fail "cd $repo"
OPSMAN_ROOT=$repo
OPSMAN_STEP_WORKTREES_DIR=$repo/.opsman/step-worktrees

# A real run gitignores .opsman/ at init-run.sh time, before any of this
# runs; mirror that precondition so the throwaway-index overlay excludes
# the scratch worktree nested under .opsman/ the same way it would in
# production, instead of git treating it as an embeddable repo.
printf '.opsman/\n' >>.gitignore
git add .gitignore
git -c user.name=t -c user.email=t@t commit -qm "gitignore .opsman"

base=$(git -C "$repo" rev-parse HEAD)
scratch=$(create_step_worktree "run1" "s1" "$base") || fail "create_step_worktree failed"
[ -d "$scratch" ] || fail "scratch worktree not created: $scratch"
assert_eq "$scratch" "$OPSMAN_STEP_WORKTREES_DIR/run1/s1" "scratch path"
git -C "$scratch" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "scratch is not a git worktree"

# overlay: untracked, modified, and deleted-relative-to-HEAD content all sync
printf 'tracked\n' >tracked.txt
git add tracked.txt
git -c user.name=t -c user.email=t@t commit -qm "add tracked"
printf 'changed\n' >tracked.txt
printf 'new\n' >untracked.txt
overlay_worktree "$repo" "$scratch" || fail "overlay_worktree failed"
assert_eq "$(cat "$scratch/tracked.txt")" "changed" "overlay syncs modified tracked file"
assert_eq "$(cat "$scratch/untracked.txt")" "new" "overlay syncs untracked file"
[ ! -e "$scratch/.opsman" ] || fail "overlay must not copy .opsman/"

# re-overlay after a deletion in src removes it from dst too
rm untracked.txt
overlay_worktree "$repo" "$scratch" || fail "overlay_worktree (delete) failed"
[ ! -e "$scratch/untracked.txt" ] || fail "overlay must propagate deletions"

# src worktree itself must be untouched by overlay (throwaway index only)
assert_eq "$(git -C "$repo" status --porcelain | LC_ALL=C sort)" \
  "$(printf ' M tracked.txt')" "overlay must not mutate the src worktree's real state"

remove_step_worktree "run1" "s1"
[ ! -d "$scratch" ] || fail "remove_step_worktree left the directory behind"
git -C "$repo" worktree list | grep -q "s1" && fail "git still tracks the removed scratch worktree"

rm tracked.txt untracked.txt 2>/dev/null || true
git -C "$repo" checkout -q -- tracked.txt 2>/dev/null || true

# --- collect-evidence.sh: --worktree override + concurrency safety ------
run_to_implementing
other_wt=$sandbox/other-wt
mkdir -p "$other_wt"
git -C "$repo" worktree add -q "$other_wt" "$(git -C "$repo" rev-parse HEAD)" \
  || fail "could not add other_wt fixture"

evdir=$("$SCRIPTS_DIR/collect-evidence.sh" --run "$run_id" --kind step --id other \
  --worktree "$other_wt" --risk R0 --cwd . --command "printf x > marker.txt")
assert_file "$evdir/meta.json"
[ -f "$other_wt/marker.txt" ] || fail "--worktree override did not execute in the given worktree"

"$SCRIPTS_DIR/collect-evidence.sh" --run "$run_id" --kind step --id concurrent-a \
  --risk R0 --cwd . --command "sleep 1; printf a > a.txt" >"$sandbox/out-a" &
pid_a=$!
"$SCRIPTS_DIR/collect-evidence.sh" --run "$run_id" --kind step --id concurrent-b \
  --risk R0 --cwd . --command "sleep 1; printf b > b.txt" >"$sandbox/out-b" &
pid_b=$!
wait "$pid_a" || fail "concurrent collect-evidence (a) failed"
wait "$pid_b" || fail "concurrent collect-evidence (b) failed"
dir_a=$(cat "$sandbox/out-a")
dir_b=$(cat "$sandbox/out-b")
[ "$dir_a" != "$dir_b" ] || fail "concurrent evidence dirs collided: $dir_a"
assert_file "$dir_a/meta.json"
assert_file "$dir_b/meta.json"

git -C "$repo" worktree remove --force "$other_wt" 2>/dev/null || rm -rf "$other_wt"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event RunAbandoned >/dev/null

# --- ready-steps.sh -------------------------------------------------------
mkskill ".claude/skills/foo2" foo2 "foo2 fixture skill"
"$SCRIPTS_DIR/build-registry.sh"
run_id=$("$SCRIPTS_DIR/init-run.sh" --no-q --base worktree "multi-step task" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsIndexed
"$SCRIPTS_DIR/classify.sh" --run "$run_id"
jq '.keywords = ["foo2"] | .domain = "dev" | .risk = "low" | .acceptance_criteria = ["ok"]' \
  "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
answer_questions_auto "$rd" "$run_id"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TaskClassified
"$SCRIPTS_DIR/select-skills.sh" --run "$run_id"
jq -n '{selected: [{skill: "foo2", role: "primary", reason: "fixture"}]}' >"$rd/selected-skills.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsSelected
jq -n '{steps: [
  {id: "ra", uses: "foo2", depends_on: [], risk: "R1", success: "ok",
   command: "printf a > a.txt", cwd: ".", allowed_files: ["a.txt"]},
  {id: "rb", uses: "foo2", depends_on: [], risk: "R1", success: "ok",
   command: "printf b > b.txt", cwd: ".", allowed_files: ["b.txt"]},
  {id: "rc-dep", uses: "foo2", depends_on: ["ra"], risk: "R1", success: "ok",
   command: "cat a.txt > c.txt", cwd: ".", allowed_files: ["c.txt"]},
  {id: "rd-manual", uses: "foo2", depends_on: [], risk: "R2", success: "agent edits"},
  {id: "re-unscoped", uses: "foo2", depends_on: [], risk: "R1", success: "ok",
   command: "true", cwd: "."},
  {id: "rf-approval", uses: "foo2", depends_on: [], risk: "R3", success: "ok",
   command: "true", cwd: ".", allowed_files: ["f.txt"]}
]}' >"$rd/plan.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event PlanCreated
jq -n '{checks: [{id: "c", command: "true", expected_exit: 0}]}' >"$rd/acceptance.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TestsDefined
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event BaselineRecorded
"$SCRIPTS_DIR/create-worktree.sh" --run "$run_id" >/dev/null

got=$("$SCRIPTS_DIR/ready-steps.sh" --run "$run_id" | jq -cS 'sort')
assert_eq "$got" '["ra","rb"]' "ready-steps: only ready, command-backed, scoped, R0-R2 steps"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event RunAbandoned >/dev/null

# max_parallel_steps caps the batch
run_id2=$("$SCRIPTS_DIR/init-run.sh" --no-q --base worktree --limit max_parallel_steps=1 \
  "capped task" | tail -n 1)
rd2=$repo/.opsman/runs/$run_id2
"$SCRIPTS_DIR/record-event.sh" --run "$run_id2" --event SkillsIndexed
"$SCRIPTS_DIR/classify.sh" --run "$run_id2"
jq '.keywords = ["foo2"] | .domain = "dev" | .risk = "low" | .acceptance_criteria = ["ok"]' \
  "$rd2/problem.yaml" >"$rd2/problem.yaml.tmp"
mv "$rd2/problem.yaml.tmp" "$rd2/problem.yaml"
answer_questions_auto "$rd2" "$run_id2"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id2" --event TaskClassified
"$SCRIPTS_DIR/select-skills.sh" --run "$run_id2"
jq -n '{selected: [{skill: "foo2", role: "primary", reason: "fixture"}]}' >"$rd2/selected-skills.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id2" --event SkillsSelected
jq -n '{steps: [
  {id: "ca", uses: "foo2", depends_on: [], risk: "R0", success: "ok",
   command: "true", cwd: ".", allowed_files: ["a.txt"]},
  {id: "cb", uses: "foo2", depends_on: [], risk: "R0", success: "ok",
   command: "true", cwd: ".", allowed_files: ["b.txt"]}
]}' >"$rd2/plan.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id2" --event PlanCreated
jq -n '{checks: [{id: "c", command: "true", expected_exit: 0}]}' >"$rd2/acceptance.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id2" --event TestsDefined
"$SCRIPTS_DIR/record-event.sh" --run "$run_id2" --event BaselineRecorded
"$SCRIPTS_DIR/create-worktree.sh" --run "$run_id2" >/dev/null
got2=$("$SCRIPTS_DIR/ready-steps.sh" --run "$run_id2" | jq -c 'length')
assert_eq "$got2" "1" "max_parallel_steps caps the returned batch"

# kernel dispatch
"$SCRIPTS_DIR/opsman" ready-steps >/dev/null

# wrong state: exit 3
"$SCRIPTS_DIR/record-event.sh" --run "$run_id2" --event RunBlocked
assert_status 3 "$SCRIPTS_DIR/ready-steps.sh" --run "$run_id2"

# --- step-run.sh ------------------------------------------------------------
mkskill ".claude/skills/foo3" foo3 "foo3 fixture skill"
"$SCRIPTS_DIR/build-registry.sh"
run_id=$("$SCRIPTS_DIR/init-run.sh" --no-q --base worktree "step-run task" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsIndexed
"$SCRIPTS_DIR/classify.sh" --run "$run_id"
jq '.keywords = ["foo3"] | .domain = "dev" | .risk = "low" | .acceptance_criteria = ["ok"]' \
  "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
answer_questions_auto "$rd" "$run_id"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TaskClassified
"$SCRIPTS_DIR/select-skills.sh" --run "$run_id"
jq -n '{selected: [{skill: "foo3", role: "primary", reason: "fixture"}]}' >"$rd/selected-skills.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsSelected
jq -n '{steps: [
  {id: "sa", uses: "foo3", depends_on: [], risk: "R1", success: "ok",
   command: "printf a > sa.txt", cwd: ".", allowed_files: ["sa.txt"]},
  {id: "sb-approval", uses: "foo3", depends_on: [], risk: "R2", success: "ok",
   command: "printf b > sb.txt # kubectl apply", cwd: ".", allowed_files: ["sb.txt"]},
  {id: "sc-dep", uses: "foo3", depends_on: ["sb-approval"], risk: "R1", success: "ok",
   command: "true", cwd: ".", allowed_files: ["sc.txt"]}
]}' >"$rd/plan.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event PlanCreated
jq -n '{checks: [{id: "c", command: "true", expected_exit: 0}]}' >"$rd/acceptance.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TestsDefined
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event BaselineRecorded
"$SCRIPTS_DIR/create-worktree.sh" --run "$run_id" >/dev/null

evdir=$("$SCRIPTS_DIR/step-run.sh" --run "$run_id" sa)
assert_file "$evdir/meta.json"
jq -es 'any(.[]; .event == "StepCompleted")' "$rd/events.jsonl" >/dev/null \
  && fail "step-run must never record StepCompleted itself"
assert_file "$rd/parallel/sa/pre.tsv"
assert_file "$rd/parallel/sa/post.tsv"
scratch=$repo/.opsman/step-worktrees/$run_id/sa
[ -f "$scratch/sa.txt" ] || fail "scratch worktree missing the step's own output"
main_wt=$(jq -r '.worktree.path' "$rd/state.json")
[ ! -f "$main_wt/sa.txt" ] || fail "step-run must not touch the main worktree"

# approval-required: refuses to execute, writes the payload, records nothing
assert_status 5 "$SCRIPTS_DIR/step-run.sh" --run "$run_id" sb-approval
assert_file "$rd/approval-required-sb-approval.json"
[ ! -f "$main_wt/sb.txt" ] || fail "approval-required step must not have executed"
jq -es 'any(.[]; .event == "HumanApprovalRequired")' "$rd/events.jsonl" >/dev/null \
  && fail "step-run must not record HumanApprovalRequired itself"

# missing dependency: exit 5, nothing recorded
assert_status 5 "$SCRIPTS_DIR/step-run.sh" --run "$run_id" sc-dep

# kernel dispatch
evdir2=$("$SCRIPTS_DIR/opsman" step-run sa)
assert_file "$evdir2/meta.json"

# wrong state
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event RunBlocked
assert_status 3 "$SCRIPTS_DIR/step-run.sh" --run "$run_id" sa

# --- step-land.sh: success path ---------------------------------------------
mkskill ".claude/skills/foo4" foo4 "foo4 fixture skill"
"$SCRIPTS_DIR/build-registry.sh"
run_id=$("$SCRIPTS_DIR/init-run.sh" --no-q --base worktree "step-land task" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsIndexed
"$SCRIPTS_DIR/classify.sh" --run "$run_id"
jq '.keywords = ["foo4"] | .domain = "dev" | .risk = "low" | .acceptance_criteria = ["ok"]' \
  "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
answer_questions_auto "$rd" "$run_id"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TaskClassified
"$SCRIPTS_DIR/select-skills.sh" --run "$run_id"
jq -n '{selected: [{skill: "foo4", role: "primary", reason: "fixture"}]}' >"$rd/selected-skills.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsSelected
jq -n '{steps: [
  {id: "la", uses: "foo4", depends_on: [], risk: "R1", success: "ok",
   command: "printf a > la.txt", cwd: ".", allowed_files: ["la.txt"]},
  {id: "lb", uses: "foo4", depends_on: [], risk: "R1", success: "ok",
   command: "printf b > lb.txt", cwd: ".", allowed_files: ["lb.txt"]},
  {id: "lc-stray", uses: "foo4", depends_on: [], risk: "R1", success: "ok",
   command: "printf x > stray.txt", cwd: ".", allowed_files: ["nope/*"]},
  {id: "ld-collide", uses: "foo4", depends_on: [], risk: "R1", success: "ok",
   command: "printf collide > la.txt", cwd: ".", allowed_files: ["la.txt"]}
]}' >"$rd/plan.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event PlanCreated
jq -n '{checks: [{id: "c", command: "true", expected_exit: 0}]}' >"$rd/acceptance.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TestsDefined
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event BaselineRecorded
"$SCRIPTS_DIR/create-worktree.sh" --run "$run_id" >/dev/null
main_wt=$(jq -r '.worktree.path' "$rd/state.json")

ev_a=$("$SCRIPTS_DIR/step-run.sh" --run "$run_id" la)
landed_a=$("$SCRIPTS_DIR/step-land.sh" --run "$run_id" --batch la,lb --evidence "$ev_a" la)
assert_eq "$landed_a" "$ev_a" "step-land prints the evidence dir on success"
assert_eq "$(cat "$main_wt/la.txt")" "a" "step-land copies the delta into the main worktree"
jq -es 'any(.[]; .event == "StepCompleted" and .payload.step_id == "la")' "$rd/events.jsonl" >/dev/null \
  || fail "StepCompleted missing for la"
assert_file "$rd/parallel/la/landed-paths.txt"
[ ! -d "$repo/.opsman/step-worktrees/$run_id/la" ] \
  || fail "step-land must remove the scratch worktree on success"

ev_b=$("$SCRIPTS_DIR/step-run.sh" --run "$run_id" lb)
"$SCRIPTS_DIR/step-land.sh" --run "$run_id" --batch la,lb --evidence "$ev_b" lb >/dev/null
assert_eq "$(cat "$main_wt/lb.txt")" "b" "second batch member lands independently"

# --- step-land.sh: scope failure (delta strays outside allowed_files) ------
ev_c=$("$SCRIPTS_DIR/step-run.sh" --run "$run_id" lc-stray)
assert_status 5 "$SCRIPTS_DIR/step-land.sh" --run "$run_id" --batch lc-stray --evidence "$ev_c" lc-stray
jq -es 'any(.[]; .event == "StepCompleted" and .payload.step_id == "lc-stray")' "$rd/events.jsonl" >/dev/null \
  && fail "scope-violating step must not record StepCompleted"
[ -d "$repo/.opsman/step-worktrees/$run_id/lc-stray" ] \
  || fail "failed land must retain the scratch worktree for diagnosis"

# --- step-land.sh: batch-sibling collision (both touch la.txt) -------------
ev_d=$("$SCRIPTS_DIR/step-run.sh" --run "$run_id" ld-collide)
assert_status 5 "$SCRIPTS_DIR/step-land.sh" --run "$run_id" --batch la,ld-collide --evidence "$ev_d" ld-collide
jq -es 'any(.[]; .event == "StepCompleted" and .payload.step_id == "ld-collide")' "$rd/events.jsonl" >/dev/null \
  && fail "colliding step must not record StepCompleted"

# a later step touching the same file, landed with a --batch that does NOT
# name "la", must NOT be flagged as a collision — landed-paths.txt for "la"
# exists on disk, but the collision check is scoped to the given --batch
# only (this is what makes normal depends_on-chain re-edits of the same
# file safe: they land through a different, later batch)
jq '.steps += [{id: "le-sequential", uses: "foo4", depends_on: ["la"], risk: "R1", success: "ok",
                command: "printf again > la.txt", cwd: ".", allowed_files: ["la.txt"]}]' \
  "$rd/plan.yaml" >"$rd/plan.yaml.tmp"
mv "$rd/plan.yaml.tmp" "$rd/plan.yaml"
ev_e=$("$SCRIPTS_DIR/step-run.sh" --run "$run_id" le-sequential)
"$SCRIPTS_DIR/step-land.sh" --run "$run_id" --batch le-sequential --evidence "$ev_e" le-sequential \
  >/dev/null
jq -es 'any(.[]; .event == "StepCompleted" and .payload.step_id == "le-sequential")' \
  "$rd/events.jsonl" >/dev/null \
  || fail "le-sequential must land despite la.txt already being landed by a different batch"
assert_eq "$(cat "$main_wt/la.txt")" "again" \
  "le-sequential's own delta (la.txt) must land since its batch doesn't collision-check against la"

# kernel dispatch
jq '.steps += [{id: "lf", uses: "foo4", depends_on: [], risk: "R1", success: "ok",
                command: "printf f > lf.txt", cwd: ".", allowed_files: ["lf.txt"]}]' \
  "$rd/plan.yaml" >"$rd/plan.yaml.tmp"
mv "$rd/plan.yaml.tmp" "$rd/plan.yaml"
ev_f=$("$SCRIPTS_DIR/opsman" step-run lf)
"$SCRIPTS_DIR/opsman" step-land --batch lf --evidence "$ev_f" lf >/dev/null
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event RunAbandoned >/dev/null

# --- end-to-end: full batch through ImplementationCompleted (worktree mode)
run_to_implementing --limit max_parallel_steps=4
jq '.steps = [
  {id: "ea", uses: "probe", depends_on: [], risk: "R1", success: "ok",
   command: "printf a > ea.txt", cwd: ".", allowed_files: ["ea.txt"]},
  {id: "eb", uses: "probe", depends_on: [], risk: "R1", success: "ok",
   command: "printf b > eb.txt", cwd: ".", allowed_files: ["eb.txt"]}
]' "$rd/plan.yaml" >"$rd/plan.yaml.tmp"
mv "$rd/plan.yaml.tmp" "$rd/plan.yaml"
batch=$("$SCRIPTS_DIR/ready-steps.sh" --run "$run_id" | jq -r 'join(",")')
assert_eq "$(printf '%s' "$batch" | tr ',' '\n' | LC_ALL=C sort | tr '\n' ',')" "ea,eb," \
  "e2e batch contains both independent steps"
ev1=$("$SCRIPTS_DIR/step-run.sh" --run "$run_id" ea)
ev2=$("$SCRIPTS_DIR/step-run.sh" --run "$run_id" eb)
"$SCRIPTS_DIR/step-land.sh" --run "$run_id" --batch "$batch" --evidence "$ev1" ea >/dev/null
"$SCRIPTS_DIR/step-land.sh" --run "$run_id" --batch "$batch" --evidence "$ev2" eb >/dev/null
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event ImplementationCompleted
assert_eq "$(jq -r '.status' "$rd/state.json")" "VALIDATING" \
  "e2e parallel batch reaches VALIDATING via the unmodified gate"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event RunAbandoned >/dev/null

# --- branch mode: scratch copy sees a step already landed by a prior round
# --base branch refuses a dirty tree at start; commit the untracked skill
# fixtures accumulated by earlier sections so the tree is clean here.
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@t commit -qm "fixture skills accumulated so far"
run_id=$("$SCRIPTS_DIR/init-run.sh" --no-q --base branch "branch mode task" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsIndexed
"$SCRIPTS_DIR/classify.sh" --run "$run_id"
jq '.keywords = ["probe"] | .domain = "dev" | .risk = "low" | .acceptance_criteria = ["ok"]' \
  "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
answer_questions_auto "$rd" "$run_id"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TaskClassified
"$SCRIPTS_DIR/select-skills.sh" --run "$run_id"
jq -n '{selected: [{skill: "probe", role: "primary", reason: "fixture"}]}' >"$rd/selected-skills.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsSelected
jq -n '{steps: [
  {id: "ba", uses: "probe", depends_on: [], risk: "R1", success: "ok",
   command: "printf a > ba.txt", cwd: ".", allowed_files: ["ba.txt"]},
  {id: "bb-reads", uses: "probe", depends_on: ["ba"], risk: "R1", success: "ok",
   command: "cat ba.txt > bb.txt", cwd: ".", allowed_files: ["bb.txt"]}
]}' >"$rd/plan.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event PlanCreated
jq -n '{checks: [{id: "c", command: "true", expected_exit: 0}]}' >"$rd/acceptance.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TestsDefined
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event BaselineRecorded
"$SCRIPTS_DIR/create-worktree.sh" --run "$run_id" >/dev/null
ev_ba=$("$SCRIPTS_DIR/step-run.sh" --run "$run_id" ba)
"$SCRIPTS_DIR/step-land.sh" --run "$run_id" --batch ba --evidence "$ev_ba" ba >/dev/null
# bb-reads depends on ba's landed output; its scratch copy must see it even
# though ba's change was never committed (branch mode never commits mid-run)
ev_bb=$("$SCRIPTS_DIR/step-run.sh" --run "$run_id" bb-reads)
scratch_bb=$repo/.opsman/step-worktrees/$run_id/bb-reads
assert_eq "$(cat "$scratch_bb/bb.txt")" "a" "branch-mode scratch copy sees prior landed edit"
"$SCRIPTS_DIR/step-land.sh" --run "$run_id" --batch bb-reads --evidence "$ev_bb" bb-reads >/dev/null
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event RunAbandoned >/dev/null
git -C "$repo" checkout -q "$(jq -r '.repository.revision' "$rd/state.json")" 2>/dev/null || true

# --- current mode: scratch copy carries the human's pre-existing dirt ------
git -C "$repo" checkout -q -b current-mode-fixture 2>/dev/null || git -C "$repo" checkout -q current-mode-fixture
printf 'human-edit\n' >human.txt
run_id=$("$SCRIPTS_DIR/init-run.sh" --no-q --base current "current mode task" | tail -n 1)
rd=$repo/.opsman/runs/$run_id
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsIndexed
"$SCRIPTS_DIR/classify.sh" --run "$run_id"
jq '.keywords = ["probe"] | .domain = "dev" | .risk = "low" | .acceptance_criteria = ["ok"]' \
  "$rd/problem.yaml" >"$rd/problem.yaml.tmp"
mv "$rd/problem.yaml.tmp" "$rd/problem.yaml"
answer_questions_auto "$rd" "$run_id"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TaskClassified
"$SCRIPTS_DIR/select-skills.sh" --run "$run_id"
jq -n '{selected: [{skill: "probe", role: "primary", reason: "fixture"}]}' >"$rd/selected-skills.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event SkillsSelected
jq -n '{steps: [{id: "ca-reads-human", uses: "probe", depends_on: [], risk: "R1", success: "ok",
                 command: "cat human.txt > ca.txt", cwd: ".", allowed_files: ["ca.txt"]}]}' \
  >"$rd/plan.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event PlanCreated
jq -n '{checks: [{id: "c", command: "true", expected_exit: 0}]}' >"$rd/acceptance.yaml"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event TestsDefined
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event BaselineRecorded
"$SCRIPTS_DIR/create-worktree.sh" --run "$run_id" >/dev/null
assert_file "$rd/baseline-dirty.tsv"
ev_ca=$("$SCRIPTS_DIR/step-run.sh" --run "$run_id" ca-reads-human)
scratch_ca=$repo/.opsman/step-worktrees/$run_id/ca-reads-human
assert_eq "$(cat "$scratch_ca/ca.txt")" "human-edit" \
  "current-mode scratch copy includes the human's pre-existing dirty file"
"$SCRIPTS_DIR/step-land.sh" --run "$run_id" --batch ca-reads-human --evidence "$ev_ca" ca-reads-human \
  >/dev/null
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event RunAbandoned >/dev/null

# --- true concurrency: two step-run.sh calls for different step ids, run
# genuinely in parallel via & / wait, must not race on git worktree add ---
run_to_implementing --limit max_parallel_steps=4
jq '.steps = [
  {id: "pa", uses: "probe", depends_on: [], risk: "R1", success: "ok",
   command: "printf a > pa.txt", cwd: ".", allowed_files: ["pa.txt"]},
  {id: "pb", uses: "probe", depends_on: [], risk: "R1", success: "ok",
   command: "printf b > pb.txt", cwd: ".", allowed_files: ["pb.txt"]}
]' "$rd/plan.yaml" >"$rd/plan.yaml.tmp"
mv "$rd/plan.yaml.tmp" "$rd/plan.yaml"
"$SCRIPTS_DIR/step-run.sh" --run "$run_id" pa >"$sandbox/ev-pa" 2>"$sandbox/err-pa" &
pid_pa=$!
"$SCRIPTS_DIR/step-run.sh" --run "$run_id" pb >"$sandbox/ev-pb" 2>"$sandbox/err-pb" &
pid_pb=$!
wait "$pid_pa" || fail "concurrent step-run.sh (pa) failed: $(cat "$sandbox/err-pa")"
wait "$pid_pb" || fail "concurrent step-run.sh (pb) failed: $(cat "$sandbox/err-pb")"
ev_pa=$(cat "$sandbox/ev-pa")
ev_pb=$(cat "$sandbox/ev-pb")
assert_file "$ev_pa/meta.json"
assert_file "$ev_pb/meta.json"
[ -f "$repo/.opsman/step-worktrees/$run_id/pa/pa.txt" ] \
  || fail "concurrent step-run.sh (pa) scratch worktree missing its own output"
[ -f "$repo/.opsman/step-worktrees/$run_id/pb/pb.txt" ] \
  || fail "concurrent step-run.sh (pb) scratch worktree missing its own output"
git -C "$repo" worktree list | grep -q "step-worktrees/$run_id/pa" \
  || fail "git lost track of the pa scratch worktree after concurrent add"
git -C "$repo" worktree list | grep -q "step-worktrees/$run_id/pb" \
  || fail "git lost track of the pb scratch worktree after concurrent add"
"$SCRIPTS_DIR/step-land.sh" --run "$run_id" --batch pa,pb --evidence "$ev_pa" pa >/dev/null
"$SCRIPTS_DIR/step-land.sh" --run "$run_id" --batch pa,pb --evidence "$ev_pb" pb >/dev/null
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event RunAbandoned >/dev/null

# --- ready-steps.sh excludes a step that already has a scratch worktree on
# disk (in flight or failed-and-left-for-diagnosis), even though it has no
# StepCompleted event yet — prevents the same id being dispatched twice ---
run_to_implementing
jq '.steps = [
  {id: "ma", uses: "probe", depends_on: [], risk: "R1", success: "ok",
   command: "printf a > ma.txt", cwd: ".", allowed_files: ["ma.txt"]},
  {id: "mb", uses: "probe", depends_on: [], risk: "R1", success: "ok",
   command: "printf b > mb.txt", cwd: ".", allowed_files: ["mb.txt"]}
]' "$rd/plan.yaml" >"$rd/plan.yaml.tmp"
mv "$rd/plan.yaml.tmp" "$rd/plan.yaml"
"$SCRIPTS_DIR/step-run.sh" --run "$run_id" ma >/dev/null
[ -d "$repo/.opsman/step-worktrees/$run_id/ma" ] \
  || fail "expected ma's scratch worktree to remain on disk before landing"
got_inflight=$("$SCRIPTS_DIR/ready-steps.sh" --run "$run_id" | jq -cS 'sort')
assert_eq "$got_inflight" '["mb"]' \
  "ready-steps must exclude ma (scratch worktree still on disk) but still offer mb"
"$SCRIPTS_DIR/record-event.sh" --run "$run_id" --event RunAbandoned >/dev/null

printf 'ok\n'
