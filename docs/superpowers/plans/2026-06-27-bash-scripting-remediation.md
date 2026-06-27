# Bash Scripting Skill Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the reviewed Bash skill defects and add executable regression coverage for every corrected helper behavior.

**Architecture:** Keep the bundled helpers dependency-free and test them through isolated Bash subprocesses. Make generated scripts inert when sourced, make lint behavior derive from each target's shebang, and keep detailed portability guidance in references rather than duplicating it in `SKILL.md`.

**Tech Stack:** Bash 3.2-compatible helper code, ShellCheck, shfmt, JSON eval metadata, Markdown references.

---

## File map

- Create `plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh`: executable regression harness for helper behavior.
- Modify `plugins/bash-scripting/skills/bash-scripting/scripts/bash-scaffold.sh`: emit a source-safe template and argument-safe logs.
- Modify `plugins/bash-scripting/skills/bash-scripting/scripts/bash-lint.sh`: discover common shell file forms and select syntax parser from the shebang.
- Modify `plugins/bash-scripting/skills/bash-scripting/scripts/bash-doc-discover.sh`: reject invalid arguments and use the current POSIX URL.
- Modify `plugins/bash-scripting/skills/bash-scripting/scripts/bash-version-check.sh`: reject invalid arguments.
- Modify `plugins/bash-scripting/skills/bash-scripting/SKILL.md`: explain strict mode without recommending source-time side effects.
- Modify `plugins/bash-scripting/skills/bash-scripting/references/01-strict-mode-and-structure.md`: document source-safe initialization.
- Modify `plugins/bash-scripting/skills/bash-scripting/references/02-defensive-patterns.md`: make command rendering and temporary-file examples safe.
- Modify `plugins/bash-scripting/skills/bash-scripting/references/04-debugging-and-testing.md`: document the executable helper regression gate.
- Modify `plugins/bash-scripting/skills/bash-scripting/references/05-portability-posix.md`: correct GNU/BSD portability claims.
- Modify `plugins/bash-scripting/skills/bash-scripting/evals/evals.json`: require source safety and conditional cleanup.

### Task 1: Source-safe scaffold and logging

**Files:**
- Create: `plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh`
- Modify: `plugins/bash-scripting/skills/bash-scripting/scripts/bash-scaffold.sh`

- [ ] **Step 1: Write scaffold regression tests**

Create the harness with these scaffold tests:

```bash
#!/usr/bin/env bash
set -uo pipefail

readonly EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly SKILL_DIR="$(cd "${EVAL_DIR}/.." >/dev/null 2>&1 && pwd)"
readonly SCRIPTS_DIR="${SKILL_DIR}/scripts"
readonly TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/bash-scripting-evals.XXXXXX")"

cleanup() {
  rm -rf -- "${TEST_TMP}"
}
trap cleanup EXIT

failures=0

run_test() {
  local name="$1"
  local function_name="$2"
  if "${function_name}"; then
    printf 'ok - %s\n' "${name}"
  else
    printf 'not ok - %s\n' "${name}" >&2
    failures=$((failures + 1))
  fi
}

generate_scaffold() {
  bash "${SCRIPTS_DIR}/bash-scaffold.sh" \
    --name regression \
    --description "Regression fixture" \
    >"${TEST_TMP}/generated.sh"
}

test_scaffold_parses() {
  generate_scaffold &&
    bash -n "${TEST_TMP}/generated.sh"
}

test_scaffold_is_source_safe() {
  generate_scaffold || return 1
  bash -c '
    before_flags=$-
    before_pipefail=$(set -o | awk '\''$1 == "pipefail" { print $2 }'\'')
    before_ifs=$(printf "%q" "${IFS}")
    before_traps=$(trap -p EXIT INT TERM)

    source "$1"

    after_flags=$-
    after_pipefail=$(set -o | awk '\''$1 == "pipefail" { print $2 }'\'')
    after_ifs=$(printf "%q" "${IFS}")
    after_traps=$(trap -p EXIT INT TERM)

    set +Eeuo pipefail
    [[ "${before_flags}" == "${after_flags}" ]]
    [[ "${before_pipefail}" == "${after_pipefail}" ]]
    [[ "${before_ifs}" == "${after_ifs}" ]]
    [[ "${before_traps}" == "${after_traps}" ]]
  ' _ "${TEST_TMP}/generated.sh"
}

test_scaffold_log_is_one_line() {
  generate_scaffold || return 1
  local output
  output="$(
    bash -c '
      source "$1"
      log INFO alpha beta
    ' _ "${TEST_TMP}/generated.sh" 2>&1
  )"
  [[ "$(printf '%s\n' "${output}" | wc -l | tr -d ' ')" == "1" ]] &&
    [[ "${output}" == *"[INFO] alpha beta" ]]
}

test_scaffold_dry_run_preserves_arguments() {
  generate_scaffold || return 1
  local output
  output="$(
    bash -c '
      source "$1"
      DRY_RUN=1
      run printf "%s\n" "a b" "*"
    ' _ "${TEST_TMP}/generated.sh" 2>&1
  )"
  [[ "$(printf '%s\n' "${output}" | wc -l | tr -d ' ')" == "1" ]] &&
    [[ "${output}" == *"a\\ b"* ]] &&
    [[ "${output}" == *"\\*"* ]]
}

run_test "generated scaffold parses" test_scaffold_parses
run_test "generated scaffold is source-safe" test_scaffold_is_source_safe
run_test "logging stays on one line" test_scaffold_log_is_one_line
run_test "dry-run preserves argument boundaries" test_scaffold_dry_run_preserves_arguments

if ((failures > 0)); then
  printf '%s test(s) failed\n' "${failures}" >&2
  exit 1
fi

printf 'All helper regression tests passed.\n'
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
/opt/homebrew/bin/bash plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh
```

Expected: non-zero status; source-safety, logging, and dry-run assertions fail against the current scaffold.

- [ ] **Step 3: Make generated initialization source-safe**

In the generated template, remove top-level `set -Eeuo pipefail`, global `IFS`, and top-level trap registration. Replace the logging, cleanup, run wrapper, and direct-execution block with:

```bash
log() {
  local level="$1"
  shift
  printf '%s [%s]' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "${level}" >&2
  printf ' %s' "$@" >&2
  printf '\n' >&2
}
log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
die() {
  log_error "$@"
  exit 1
}

cleanup() {
  local rc=$?
  trap - EXIT
  exit "${rc}"
}

install_traps() {
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

DRY_RUN=0
run() {
  if ((DRY_RUN)); then
    printf 'DRY-RUN:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
  else
    "$@"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -Eeuo pipefail
  install_traps
  main "$@"
fi
```

Update the scaffold's own header comments to say it emits manual long-option parsing and installs strict mode/traps only for direct execution.

- [ ] **Step 4: Run the scaffold tests and verify GREEN**

Run:

```bash
/opt/homebrew/bin/bash plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh
```

Expected: `All helper regression tests passed.`

- [ ] **Step 5: Lint the implementation**

Run:

```bash
shellcheck \
  plugins/bash-scripting/skills/bash-scripting/scripts/bash-scaffold.sh \
  plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh
shfmt -i 2 -ci -d \
  plugins/bash-scripting/skills/bash-scripting/scripts/bash-scaffold.sh \
  plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh
```

Expected: both commands exit 0 with no findings or diff.

- [ ] **Step 6: Commit**

```bash
git add \
  plugins/bash-scripting/skills/bash-scripting/scripts/bash-scaffold.sh \
  plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh
git commit -m "Fix Bash scaffold source safety"
```

### Task 2: Dialect-aware linting and file discovery

**Files:**
- Modify: `plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh`
- Modify: `plugins/bash-scripting/skills/bash-scripting/scripts/bash-lint.sh`

- [ ] **Step 1: Add failing linter tests**

Add these functions before the harness's `run_test` calls:

```bash
create_lint_fixtures() {
  local fixture_dir="${TEST_TMP}/lint-fixtures"
  mkdir -p "${fixture_dir}"
  printf '#!/usr/bin/env bash\nprintf "sh\\n"\n' >"${fixture_dir}/sample.sh"
  printf '#!/usr/bin/env bash\nprintf "bash\\n"\n' >"${fixture_dir}/sample.bash"
  printf '#!/bin/sh\nprintf "runner\\n"\n' >"${fixture_dir}/runner"
  chmod +x "${fixture_dir}/runner"
}

test_lint_discovers_shell_files() {
  create_lint_fixtures || return 1
  local output
  output="$(
    bash "${SCRIPTS_DIR}/bash-lint.sh" \
      --no-shellcheck \
      --no-shfmt \
      "${TEST_TMP}/lint-fixtures" 2>&1
  )"
  [[ "${output}" == *"3 file(s)"* ]]
}

test_lint_uses_posix_parser() {
  create_lint_fixtures || return 1
  local output
  output="$(
    bash "${SCRIPTS_DIR}/bash-lint.sh" \
      --no-shellcheck \
      --no-shfmt \
      "${TEST_TMP}/lint-fixtures/sample.sh" 2>&1
  )"
  [[ "${output}" == *"[ok]   sh -n"* ]] &&
    [[ "${output}" == *"portability: NOT CHECKED"* ]]
}
```

Change `sample.sh` in `create_lint_fixtures` to use `#!/bin/sh`, then add:

```bash
run_test "linter discovers common shell files" test_lint_discovers_shell_files
run_test "linter selects the POSIX parser" test_lint_uses_posix_parser
```

- [ ] **Step 2: Run the new tests and verify RED**

Run the full harness.

Expected: the discovery test sees one file instead of three, and the dialect test sees `bash -n` instead of `sh -n`.

- [ ] **Step 3: Implement shell-file detection**

Replace `collect_scripts()` with:

```bash
is_shell_script() {
  local path="$1"
  local first_line=""
  IFS= read -r first_line <"${path}" || true
  [[ "${path}" == *.sh || "${path}" == *.bash ]] ||
    [[ -x "${path}" && "${first_line}" =~ ^#!.*(bash|/sh|dash)([[:space:]]|$) ]]
}

collect_scripts() {
  local path candidate
  for path in "$@"; do
    if [[ -d "${path}" ]]; then
      while IFS= read -r -d '' candidate; do
        if is_shell_script "${candidate}"; then
          printf '%s\0' "${candidate}"
        fi
      done < <(find "${path}" -type f -print0)
    elif [[ -f "${path}" ]]; then
      printf '%s\0' "${path}"
    else
      return 2
    fi
  done
}
```

Validate every supplied path before invoking `collect_scripts` so a missing path produces one focused error from the parent shell:

```bash
for path in "${paths[@]}"; do
  [[ -e "${path}" ]] || die "no such file or directory: ${path}"
done
```

- [ ] **Step 4: Implement shebang-aware syntax checks**

Add:

```bash
syntax_parser() {
  local script="$1"
  local first_line=""
  IFS= read -r first_line <"${script}" || true
  case "${first_line}" in
    *dash*) command -v dash >/dev/null 2>&1 && printf 'dash\n' || printf 'sh\n' ;;
    *"/sh" | *"env sh"*) printf 'sh\n' ;;
    *) printf 'bash\n' ;;
  esac
}
```

Replace the hard-coded `bash -n` block with:

```bash
local parser
parser="$(syntax_parser "${script}")"
if ! "${parser}" -n "${script}"; then
  log "  [FAIL] ${parser} -n (syntax)"
  failures=$((failures + 1))
  continue
fi
log "  [ok]   ${parser} -n"
```

Track whether any POSIX script was checked without ShellCheck and emit:

```bash
log "  [warn] portability: NOT CHECKED (ShellCheck skipped or unavailable)"
```

Change the successful summary to `All requested checks passed (...)` so skipped optional checks are not represented as completed.

- [ ] **Step 5: Run tests and linters**

Run:

```bash
/opt/homebrew/bin/bash plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh
shellcheck \
  plugins/bash-scripting/skills/bash-scripting/scripts/bash-lint.sh \
  plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh
shfmt -i 2 -ci -d \
  plugins/bash-scripting/skills/bash-scripting/scripts/bash-lint.sh \
  plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh
```

Expected: all commands exit 0.

- [ ] **Step 6: Commit**

```bash
git add \
  plugins/bash-scripting/skills/bash-scripting/scripts/bash-lint.sh \
  plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh
git commit -m "Make Bash linting dialect aware"
```

### Task 3: Helper interfaces and current documentation discovery

**Files:**
- Modify: `plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh`
- Modify: `plugins/bash-scripting/skills/bash-scripting/scripts/bash-doc-discover.sh`
- Modify: `plugins/bash-scripting/skills/bash-scripting/scripts/bash-version-check.sh`

- [ ] **Step 1: Add failing interface tests**

Add:

```bash
test_helpers_reject_unexpected_arguments() {
  local helper status
  for helper in bash-doc-discover.sh bash-version-check.sh; do
    status=0
    bash "${SCRIPTS_DIR}/${helper}" unexpected >"${TEST_TMP}/${helper}.out" 2>"${TEST_TMP}/${helper}.err" || status=$?
    [[ "${status}" == "2" ]] || return 1
    grep -q '^error: unexpected argument: unexpected$' "${TEST_TMP}/${helper}.err" || return 1
  done
}

test_docs_use_current_posix_url() {
  bash "${SCRIPTS_DIR}/bash-doc-discover.sh" |
    grep -q 'https://pubs.opengroup.org/onlinepubs/9799919799/'
}
```

Register both with `run_test`.

- [ ] **Step 2: Run tests and verify RED**

Run the harness.

Expected: both new tests fail because arguments are ignored and the output contains the older `9699919799` URL.

- [ ] **Step 3: Implement strict argument handling**

Add this parser to both helpers after `usage()`:

```bash
case "${1:-}" in
  "")
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf 'error: unexpected argument: %s\n' "$1" >&2
    exit 2
    ;;
esac

if (($# > 1)); then
  printf 'error: unexpected argument: %s\n' "$2" >&2
  exit 2
fi
```

Remove the existing help-only conditional.

- [ ] **Step 4: Refresh the POSIX link**

In `bash-doc-discover.sh`, replace:

```text
https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html
```

with:

```text
https://pubs.opengroup.org/onlinepubs/9799919799/
```

- [ ] **Step 5: Run tests and linters**

Run the full helper harness, ShellCheck, and shfmt against all changed scripts.

Expected: all commands exit 0.

- [ ] **Step 6: Commit**

```bash
git add \
  plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh \
  plugins/bash-scripting/skills/bash-scripting/scripts/bash-doc-discover.sh \
  plugins/bash-scripting/skills/bash-scripting/scripts/bash-version-check.sh
git commit -m "Validate Bash helper arguments"
```

### Task 4: Correct skill guidance and eval expectations

**Files:**
- Modify: `plugins/bash-scripting/skills/bash-scripting/SKILL.md`
- Modify: `plugins/bash-scripting/skills/bash-scripting/references/01-strict-mode-and-structure.md`
- Modify: `plugins/bash-scripting/skills/bash-scripting/references/02-defensive-patterns.md`
- Modify: `plugins/bash-scripting/skills/bash-scripting/references/04-debugging-and-testing.md`
- Modify: `plugins/bash-scripting/skills/bash-scripting/references/05-portability-posix.md`
- Modify: `plugins/bash-scripting/skills/bash-scripting/evals/evals.json`

- [ ] **Step 1: Update strict-mode guidance**

Replace the `SKILL.md` heading `Always start with strict mode` with `Use strict mode for standalone execution`. State explicitly:

```markdown
For a standalone executable, enable `set -Eeuo pipefail` immediately before entering `main`. For a file intended to be sourced, do not change the caller's shell options, `IFS`, or traps at import time; expose an explicit initializer instead.
```

Remove the global `IFS=$'\n\t'` recommendation and correct the scaffold description from `getopts` to a manual `while`/`case` long-option parser.

Mirror this source-safety contract in `references/01-strict-mode-and-structure.md`, including the direct-execution block used by the fixed scaffold.

- [ ] **Step 2: Correct defensive and portability examples**

In `references/02-defensive-patterns.md`:

- Use `mktemp -d "${TMPDIR:-/tmp}/script-name.XXXXXX"`.
- Use `rm -rf -- "${work_dir}"`.
- Replace `$*` dry-run rendering with repeated `printf ' %q' "$@"`.
- Describe `ln -sfn` as replacement, not atomic replacement.

In `references/05-portability-posix.md`:

- Replace `grealink` with `greadlink`.
- Replace `mktemp -t prefix` with an explicit `XXXXXX` template under `${TMPDIR:-/tmp}`.
- Replace the claim that `xargs -0` skips empty input with `find ... -exec command {} +`.
- Link to POSIX.1-2024 Issue 8.

- [ ] **Step 3: Document executable eval coverage**

In `references/04-debugging-and-testing.md`, add:

```markdown
## Testing the bundled helpers

Run `bash evals/test-helpers.sh` after changing this skill's helper scripts. The harness checks generated-script source safety, argument-preserving logs, shell-file discovery, dialect selection, helper usage errors, and documentation routing without requiring Bats or network access.
```

- [ ] **Step 4: Update eval expectations**

In eval 1, replace the unconditional trap requirement with:

```text
Use trap-based cleanup only when the script creates temporary resources. A main/source guard must not change the caller's shell options, IFS, or traps when sourced.
```

Keep the JSON valid and retain the remaining safety expectations.

- [ ] **Step 5: Validate documentation and metadata**

Run:

```bash
python3 -m json.tool plugins/bash-scripting/skills/bash-scripting/evals/evals.json >/dev/null
rg -n 'grealink|mktemp -t prefix|xargs -0.*skips empty|Always start with strict mode|IFS=\\$' \
  plugins/bash-scripting/skills/bash-scripting
```

Expected: JSON validation exits 0; `rg` finds no stale guidance.

- [ ] **Step 6: Commit**

```bash
git add \
  plugins/bash-scripting/skills/bash-scripting/SKILL.md \
  plugins/bash-scripting/skills/bash-scripting/evals/evals.json \
  plugins/bash-scripting/skills/bash-scripting/references
git commit -m "Correct Bash skill safety guidance"
```

### Task 5: Full verification

**Files:**
- Verify all files changed in Tasks 1-4.

- [ ] **Step 1: Run executable regressions**

```bash
/opt/homebrew/bin/bash plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh
```

Expected: `All helper regression tests passed.`

- [ ] **Step 2: Run the skill validator**

```bash
UV_CACHE_DIR=/tmp/codex-uv-cache uv run --python /usr/bin/python3 --with pyyaml \
  python /Users/vladtara/.codex/skills/.system/skill-creator/scripts/quick_validate.py \
  plugins/bash-scripting/skills/bash-scripting
```

Expected: `Skill is valid!`

- [ ] **Step 3: Run repository validators with compatible tooling**

```bash
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin /opt/homebrew/bin/bash .ci/validate-structure.sh
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin /opt/homebrew/bin/bash .ci/validate-marketplace-sync.sh
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin /opt/homebrew/bin/bash .ci/validate-json.sh
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin /opt/homebrew/bin/bash .ci/validate-markdown-internal-links.sh
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin /opt/homebrew/bin/bash .ci/validate-shell-syntax.sh
```

Expected: every validator reports `passed`.

- [ ] **Step 4: Run helper quality gates**

```bash
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin \
  /opt/homebrew/bin/bash \
  plugins/bash-scripting/skills/bash-scripting/scripts/bash-lint.sh \
  plugins/bash-scripting/skills/bash-scripting/scripts \
  plugins/bash-scripting/skills/bash-scripting/evals/test-helpers.sh
```

Expected: all requested checks pass with no ShellCheck or shfmt findings.

- [ ] **Step 5: Inspect the final diff**

```bash
git diff --check
git status --short
git log --oneline -5
```

Expected: no whitespace errors; only intentional files are modified or committed; recent commits correspond to the design and remediation tasks.
