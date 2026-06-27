# CI/CD Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ad-hoc `.ci/` validators with a script-canonical CI/CD system: `scripts/` holds all logic, pre-commit and GitHub Actions both invoke those scripts, and a tag-driven release workflow publishes GitHub Releases with a generated changelog.

**Architecture:** All developer commands are shell scripts under `scripts/`, runnable from the repo root. A shared `scripts/lib/common.sh` provides logging and tool-detection helpers. The existing five `.ci/` validators move under `scripts/checks/` and are orchestrated by `scripts/validate.sh`. Pre-commit hooks and CI jobs call the same scripts, so local validation matches CI by construction. Releases are repo-level semver tags that trigger a workflow generating a git-cliff changelog and a GitHub Release.

**Tech Stack:** Bash, Python 3 (for existing JSON/link validators), GitHub Actions, pre-commit, and CLI tools: shellcheck, shfmt, yamllint, actionlint, prettier, markdownlint-cli2, gitleaks, git-cliff.

## Global Constraints

- No Makefile / `make`. Local commands are shell scripts only.
- Every script: `#!/usr/bin/env bash`, `set -euo pipefail`, quoted variables, runs from repo root via `git rev-parse --show-toplevel`, supports `-h/--help`.
- Canonical formatting: `shfmt -i 2 -ci -bn` (2-space indent, switch-case indent, binary ops at line start). All scripts must be shfmt-clean and shellcheck-clean.
- All checks operate on **git-tracked files only** (`git ls-files`). Stage files before validating.
- **prettier is scoped to JSON + YAML only** — never Markdown (Markdown is authored prose; markdownlint lints it, nothing auto-reformats it).
- A missing tool is **skipped with a warning locally** but is **fatal when `CI=true`** (bootstrap installs everything in CI).
- Git identity for all commits: `vladtara <vlad@glaps.fun>`. **Never add co-author trailers.**
- Least-privilege GitHub Actions permissions: `contents: read` for CI, `contents: write` only on the release job.
- Out of scope (do not add): TOML validation, GoReleaser, binary artifacts, checksums.
- Commit messages use conventional prefixes (`feat:`, `fix:`, `ci:`, `chore:`, `docs:`) so git-cliff can group them.

---

### Task 1: Shared library and bootstrap script

**Files:**
- Create: `scripts/lib/common.sh`
- Create: `scripts/bootstrap.sh`

**Interfaces:**
- Produces (sourced by every later script via `source "$SCRIPT_DIR/lib/common.sh"`):
  - `REPO_ROOT` — absolute repo root, exported.
  - `log_info MSG`, `log_warn MSG`, `log_error MSG`, `log_ok MSG` — write to stderr.
  - `have_tool NAME` — exit 0 if `NAME` on PATH.
  - `require_tool NAME [HINT]` — `exit 1` with message if missing.
  - `skip_unless_tool NAME` — returns 0 if present; if missing, `exit 1` when `CI=true`, else `log_warn` and return 1.
- Produces: `scripts/bootstrap.sh [--ci]` installs all tooling.

- [ ] **Step 1: Write `scripts/lib/common.sh`**

```bash
#!/usr/bin/env bash
# Shared helpers for cnative-skills developer scripts.
# Source this file from other scripts; do not execute it directly.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
export REPO_ROOT

log_info() { printf '\033[0;34m[info]\033[0m  %s\n' "$*" >&2; }
log_warn() { printf '\033[0;33m[warn]\033[0m  %s\n' "$*" >&2; }
log_error() { printf '\033[0;31m[error]\033[0m %s\n' "$*" >&2; }
log_ok() { printf '\033[0;32m[ok]\033[0m    %s\n' "$*" >&2; }

# have_tool NAME -> 0 if NAME is on PATH.
have_tool() { command -v "$1" >/dev/null 2>&1; }

# require_tool NAME [HINT] -> exit 1 if NAME is missing.
require_tool() {
  if ! have_tool "$1"; then
    log_error "required tool '$1' not found. ${2:-Install it and retry.}"
    exit 1
  fi
}

# skip_unless_tool NAME -> 0 if present. If missing: fatal in CI, else warn+return 1.
skip_unless_tool() {
  if have_tool "$1"; then
    return 0
  fi
  if [[ "${CI:-}" == "true" ]]; then
    log_error "tool '$1' missing in CI; scripts/bootstrap.sh --ci should have installed it"
    exit 1
  fi
  log_warn "tool '$1' not found; skipping its checks. Run scripts/bootstrap.sh to install."
  return 1
}
```

- [ ] **Step 2: Verify common.sh is shellcheck- and shfmt-clean**

Run: `shellcheck scripts/lib/common.sh && shfmt -i 2 -ci -bn -d scripts/lib/common.sh`
Expected: no output, exit 0.

- [ ] **Step 3: Write `scripts/bootstrap.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SHFMT_VERSION="v3.10.0"
ACTIONLINT_VERSION="v1.7.7"
GITLEAKS_VERSION="v8.21.2"

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap.sh [--ci]

Install developer tooling used by the scripts/ check suite:
  shellcheck shfmt yamllint actionlint prettier markdownlint-cli2
  gitleaks pre-commit (and git-cliff on macOS for local release dry-runs).

Options:
  --ci        Non-interactive install for Linux CI runners (apt/go/npm/pip).
  -h, --help  Show this help.

With no flag, installs via Homebrew on macOS.
EOF
}

bootstrap_macos() {
  require_tool brew "Install Homebrew from https://brew.sh"
  brew install \
    shellcheck shfmt yamllint actionlint \
    prettier markdownlint-cli2 gitleaks git-cliff pre-commit
}

bootstrap_ci() {
  require_tool go "Go must be available on the CI runner"
  require_tool npm "Node/npm must be available on the CI runner"
  require_tool python3 "Python 3 must be available on the CI runner"

  sudo apt-get update -y
  sudo apt-get install -y shellcheck

  go install "mvdan.cc/sh/v3/cmd/shfmt@${SHFMT_VERSION}"
  go install "github.com/rhysd/actionlint/cmd/actionlint@${ACTIONLINT_VERSION}"
  go install "github.com/gitleaks/gitleaks/v8@${GITLEAKS_VERSION}"

  python3 -m pip install --user --quiet yamllint pre-commit
  npm install -g --no-fund --no-audit prettier markdownlint-cli2

  # Persist tool locations to later workflow steps (git-cliff is provided by
  # the release workflow's action, so it is intentionally not installed here).
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$(go env GOPATH)/bin" >>"$GITHUB_PATH"
    echo "$HOME/.local/bin" >>"$GITHUB_PATH"
  fi
}

main() {
  case "${1:-}" in
    --ci) bootstrap_ci ;;
    -h | --help)
      usage
      exit 0
      ;;
    "")
      case "$(uname -s)" in
        Darwin) bootstrap_macos ;;
        *)
          log_error "Automated local install supports macOS only; use --ci or install tools manually."
          exit 1
          ;;
      esac
      ;;
    *)
      log_error "unknown argument: $1"
      usage
      exit 2
      ;;
  esac
  log_ok "bootstrap complete"
}

main "$@"
```

- [ ] **Step 4: Make scripts executable and verify clean**

Run:
```bash
chmod +x scripts/lib/common.sh scripts/bootstrap.sh
shellcheck scripts/bootstrap.sh && shfmt -i 2 -ci -bn -d scripts/bootstrap.sh
scripts/bootstrap.sh --help
```
Expected: shellcheck/shfmt produce no output; `--help` prints usage and exits 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/common.sh scripts/bootstrap.sh
git -c user.name=vladtara -c user.email=vlad@glaps.fun commit -m "feat: add shared script library and bootstrap"
```

---

### Task 2: Move validators, add YAML check, build validate.sh

**Files:**
- Move: `.ci/validate-structure.sh` → `scripts/checks/structure.sh`
- Move: `.ci/validate-marketplace-sync.sh` → `scripts/checks/marketplace-sync.sh`
- Move: `.ci/validate-json.sh` → `scripts/checks/json.sh`
- Move: `.ci/validate-markdown-internal-links.sh` → `scripts/checks/markdown-links.sh`
- Move: `.ci/validate-shell-syntax.sh` → `scripts/checks/shell-syntax.sh`
- Create: `scripts/checks/yaml.sh`
- Create: `scripts/validate.sh`
- Create: `.yamllint`
- Modify: `.github/workflows/ci.yml` (interim: call `scripts/validate.sh`)
- Delete: `.ci/` (now empty)

**Interfaces:**
- Consumes: `scripts/lib/common.sh` helpers (Task 1).
- Produces: `scripts/validate.sh [--fast|--slow|--all]`. Fast = `structure marketplace-sync json yaml shell-syntax`; slow = `markdown-links`; all = both. Each `scripts/checks/<name>.sh` is independently runnable and exits non-zero on failure.

- [ ] **Step 1: Move the five validators (preserves git history)**

Run:
```bash
mkdir -p scripts/checks
git mv .ci/validate-structure.sh           scripts/checks/structure.sh
git mv .ci/validate-marketplace-sync.sh    scripts/checks/marketplace-sync.sh
git mv .ci/validate-json.sh                scripts/checks/json.sh
git mv .ci/validate-markdown-internal-links.sh scripts/checks/markdown-links.sh
git mv .ci/validate-shell-syntax.sh        scripts/checks/shell-syntax.sh
```
The moved scripts already locate the repo via `git rev-parse --show-toplevel`, so they need no edits.
Expected: `ls .ci` shows the directory is now empty; `git status` shows five renames.

- [ ] **Step 2: Verify the moved scripts still run from their new location**

Run: `for c in structure marketplace-sync json shell-syntax; do bash "scripts/checks/$c.sh"; done`
Expected: each prints its existing success line (e.g. "Structure validation passed for 7 plugin(s).") and exits 0.

- [ ] **Step 3: Write `.yamllint`**

```yaml
extends: default

rules:
  document-start: disable
  line-length:
    max: 120
    level: warning
  comments:
    min-spaces-from-content: 1
  truthy:
    check-keys: false
```

- [ ] **Step 4: Write `scripts/checks/yaml.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

cd "$REPO_ROOT"

mapfile -t yaml_files < <(git ls-files '*.yml' '*.yaml')

if [[ ${#yaml_files[@]} -eq 0 ]]; then
  log_info "no tracked YAML files"
  exit 0
fi

skip_unless_tool yamllint || exit 0

yamllint -c .yamllint -- "${yaml_files[@]}"
log_ok "YAML lint passed for ${#yaml_files[@]} file(s)"
```

- [ ] **Step 5: Write `scripts/validate.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

FAST_CHECKS=(structure marketplace-sync json yaml shell-syntax)
SLOW_CHECKS=(markdown-links)

usage() {
  cat <<'EOF'
Usage: scripts/validate.sh [--fast|--slow|--all]

Run repository validation checks from scripts/checks/.
  --fast      Structure, marketplace sync, JSON, YAML, shell syntax (default).
  --slow      Markdown internal links.
  --all       Fast and slow checks.
  -h, --help  Show this help.
EOF
}

mode="fast"
case "${1:-}" in
  --fast | "") mode="fast" ;;
  --slow) mode="slow" ;;
  --all) mode="all" ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    log_error "unknown argument: $1"
    usage
    exit 2
    ;;
esac

case "$mode" in
  fast) checks=("${FAST_CHECKS[@]}") ;;
  slow) checks=("${SLOW_CHECKS[@]}") ;;
  all) checks=("${FAST_CHECKS[@]}" "${SLOW_CHECKS[@]}") ;;
esac

failed=0
for check in "${checks[@]}"; do
  log_info "validate: $check"
  if ! bash "$SCRIPT_DIR/checks/$check.sh"; then
    failed=$((failed + 1))
  fi
done

if ((failed > 0)); then
  log_error "$failed validation check(s) failed"
  exit 1
fi

log_ok "validation passed ($mode)"
```

- [ ] **Step 6: Update `.github/workflows/ci.yml` (interim) so CI stays green**

Replace the five `Validate …` steps (the steps running `bash .ci/…`) with a single step:
```yaml
      - name: Validate repository
        run: scripts/validate.sh --all
```
Leave `name`, `on`, `permissions`, and the checkout step unchanged. (Task 8 rewrites this file into the full fast/slow structure.)

- [ ] **Step 7: Make executable, verify, and confirm `.ci/` is gone**

Run:
```bash
chmod +x scripts/checks/yaml.sh scripts/validate.sh
shellcheck scripts/checks/yaml.sh scripts/validate.sh
shfmt -i 2 -ci -bn -d scripts/checks/yaml.sh scripts/validate.sh
scripts/validate.sh --all
rmdir .ci
```
Expected: shellcheck/shfmt silent; `validate.sh --all` ends with "validation passed (all)"; `rmdir .ci` succeeds (directory empty).

- [ ] **Step 8: Commit**

```bash
git add -A
git -c user.name=vladtara -c user.email=vlad@glaps.fun commit -m "ci: move validators under scripts/checks and add validate.sh"
```

---

### Task 3: Formatting (fmt.sh)

**Files:**
- Create: `scripts/fmt.sh`
- Create: `.prettierignore`

**Interfaces:**
- Consumes: `scripts/lib/common.sh`.
- Produces: `scripts/fmt.sh [--check]`. Default rewrites in place; `--check` exits non-zero on any unformatted file. Formats shell via `shfmt -i 2 -ci -bn` and JSON/YAML via prettier. Never touches Markdown.

- [ ] **Step 1: Write `.prettierignore`**

```text
# Authored Markdown is linted (markdownlint), never auto-formatted.
*.md
# Vendored / generated trees, if any, go here.
```

- [ ] **Step 2: Write `scripts/fmt.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SHFMT_FLAGS=(-i 2 -ci -bn)

usage() {
  cat <<'EOF'
Usage: scripts/fmt.sh [--check]

Format shell scripts (shfmt) and JSON/YAML (prettier).
  --check     Report unformatted files and exit non-zero; do not write.
  -h, --help  Show this help.
EOF
}

check=false
case "${1:-}" in
  --check) check=true ;;
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    log_error "unknown argument: $1"
    usage
    exit 2
    ;;
esac

cd "$REPO_ROOT"
status=0

if skip_unless_tool shfmt; then
  mapfile -t sh_files < <(git ls-files '*.sh')
  if [[ ${#sh_files[@]} -gt 0 ]]; then
    if "$check"; then
      shfmt "${SHFMT_FLAGS[@]}" -d -- "${sh_files[@]}" || status=1
    else
      shfmt "${SHFMT_FLAGS[@]}" -w -- "${sh_files[@]}"
    fi
  fi
fi

if skip_unless_tool prettier; then
  mapfile -t fmt_files < <(git ls-files '*.json' '*.yml' '*.yaml')
  if [[ ${#fmt_files[@]} -gt 0 ]]; then
    if "$check"; then
      prettier --check --ignore-path .prettierignore -- "${fmt_files[@]}" || status=1
    else
      prettier --write --ignore-path .prettierignore -- "${fmt_files[@]}"
    fi
  fi
fi

if ((status != 0)); then
  log_error "formatting issues found; run scripts/fmt.sh to fix"
  exit 1
fi
log_ok "formatting ok"
```

- [ ] **Step 3: Make executable, verify clean, normalize the repo**

Run:
```bash
chmod +x scripts/fmt.sh
shellcheck scripts/fmt.sh && shfmt -i 2 -ci -bn -d scripts/fmt.sh
scripts/fmt.sh           # rewrites any unformatted shell/JSON/YAML
git status               # review the one-time normalization diff
scripts/fmt.sh --check   # must now report clean
```
Expected: `--check` exits 0 after the rewrite. The normalization diff (if any) is expected and committed below.

- [ ] **Step 4: Commit**

```bash
git add -A
git -c user.name=vladtara -c user.email=vlad@glaps.fun commit -m "chore: add fmt.sh and normalize shell/JSON/YAML formatting"
```

---

### Task 4: Linting (lint.sh)

**Files:**
- Create: `scripts/lint.sh`
- Create: `.markdownlint-cli2.yaml`

**Interfaces:**
- Consumes: `scripts/lib/common.sh`, `.yamllint` (Task 2).
- Produces: `scripts/lint.sh` running shellcheck, yamllint, markdownlint-cli2, actionlint; exits non-zero if any reports problems.

- [ ] **Step 1: Write `.markdownlint-cli2.yaml`**

```yaml
config:
  default: true
  MD013: false   # line length: prose is wrapped by author preference
  MD033: false   # inline HTML is allowed in skill docs
  MD041: false   # first line need not be a top-level heading
globs:
  - "**/*.md"
ignores:
  - "**/node_modules/**"
```

- [ ] **Step 2: Write `scripts/lint.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/lint.sh

Lint shell (shellcheck), YAML (yamllint), Markdown (markdownlint-cli2),
and GitHub Actions workflows (actionlint). Operates on git-tracked files.
  -h, --help  Show this help.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    log_error "unknown argument: $1"
    usage
    exit 2
    ;;
esac

cd "$REPO_ROOT"
status=0

if skip_unless_tool shellcheck; then
  mapfile -t sh_files < <(git ls-files '*.sh')
  if [[ ${#sh_files[@]} -gt 0 ]]; then
    shellcheck -- "${sh_files[@]}" || status=1
  fi
fi

if skip_unless_tool yamllint; then
  mapfile -t yaml_files < <(git ls-files '*.yml' '*.yaml')
  if [[ ${#yaml_files[@]} -gt 0 ]]; then
    yamllint -c .yamllint -- "${yaml_files[@]}" || status=1
  fi
fi

if skip_unless_tool markdownlint-cli2; then
  markdownlint-cli2 || status=1
fi

if skip_unless_tool actionlint; then
  actionlint || status=1
fi

if ((status != 0)); then
  log_error "lint problems found"
  exit 1
fi
log_ok "lint passed"
```

- [ ] **Step 3: Make executable, verify clean, fix any findings**

Run:
```bash
chmod +x scripts/lint.sh
shellcheck scripts/lint.sh && shfmt -i 2 -ci -bn -d scripts/lint.sh
scripts/lint.sh
```
Expected: `scripts/lint.sh` exits 0. If shellcheck/markdownlint/yamllint report real issues in existing files, fix them now (or, for a deliberate exception, add a scoped disable directive) until the script passes.

- [ ] **Step 4: Commit**

```bash
git add -A
git -c user.name=vladtara -c user.email=vlad@glaps.fun commit -m "ci: add lint.sh with shellcheck, yamllint, markdownlint, actionlint"
```

---

### Task 5: Orchestrator and tests (check.sh, test.sh)

**Files:**
- Create: `scripts/test.sh`
- Create: `scripts/check.sh`

**Interfaces:**
- Consumes: `scripts/fmt.sh`, `scripts/lint.sh`, `scripts/validate.sh` (and, referenced for `--all`, `scripts/test.sh`, `scripts/install-test.sh`, `scripts/security.sh` from Task 6).
- Produces:
  - `scripts/test.sh` — validates every `plugins/*/skills/*/evals/evals.json` has `skill_name` (string) and `evals` (array), each eval with non-empty `id` and `prompt`.
  - `scripts/check.sh [--all]` — fast suite by default (`fmt --check`, `lint`, `validate --fast`); `--all` adds `validate --slow`, `test`, `install-test`, `security`.

- [ ] **Step 1: Write `scripts/test.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/test.sh

Validate the shape of every tracked evals.json against the skill eval schema.
  -h, --help  Show this help.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    log_error "unknown argument: $1"
    usage
    exit 2
    ;;
esac

cd "$REPO_ROOT"
require_tool python3

python3 <<'PY'
import json
import subprocess
import sys

tracked = subprocess.run(
    ["git", "ls-files"], check=True, capture_output=True, text=True
).stdout.splitlines()

eval_files = sorted(
    p for p in tracked if p.endswith("/evals/evals.json")
)

if not eval_files:
    print("No tracked evals.json files found.")
    sys.exit(0)

errors = []

for path in eval_files:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as exc:
        errors.append(f"{path}: invalid JSON: {exc}")
        continue

    if not isinstance(data.get("skill_name"), str) or not data["skill_name"].strip():
        errors.append(f"{path}: missing non-empty 'skill_name'")

    evals = data.get("evals")
    if not isinstance(evals, list) or not evals:
        errors.append(f"{path}: 'evals' must be a non-empty array")
        continue

    for i, item in enumerate(evals):
        loc = f"{path} (evals[{i}])"
        if not isinstance(item, dict):
            errors.append(f"{loc}: must be an object")
            continue
        for field in ("id", "prompt"):
            if not isinstance(item.get(field), str) or not item[field].strip():
                errors.append(f"{loc}: missing non-empty '{field}'")

if errors:
    for e in errors:
        print(f"::error::{e}")
    sys.exit(1)

print(f"Eval schema validation passed for {len(eval_files)} file(s).")
PY
log_ok "tests passed"
```

- [ ] **Step 2: Write `scripts/check.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/check.sh [--all]

Run the developer check suite.
  (default)   Fast suite: fmt --check, lint, validate --fast.
  --all       Everything CI runs: also validate --slow, test, install-test, security.
  -h, --help  Show this help.
EOF
}

all=false
case "${1:-}" in
  --all) all=true ;;
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    log_error "unknown argument: $1"
    usage
    exit 2
    ;;
esac

run() {
  log_info "==> $*"
  "$@"
}

run "$SCRIPT_DIR/fmt.sh" --check
run "$SCRIPT_DIR/lint.sh"
run "$SCRIPT_DIR/validate.sh" --fast

if "$all"; then
  run "$SCRIPT_DIR/validate.sh" --slow
  run "$SCRIPT_DIR/test.sh"
  run "$SCRIPT_DIR/install-test.sh"
  run "$SCRIPT_DIR/security.sh"
fi

log_ok "all checks passed"
```

- [ ] **Step 3: Make executable and verify the fast suite**

Run:
```bash
chmod +x scripts/test.sh scripts/check.sh
shellcheck scripts/test.sh scripts/check.sh
shfmt -i 2 -ci -bn -d scripts/test.sh scripts/check.sh
scripts/test.sh
scripts/check.sh
```
Expected: shellcheck/shfmt silent; `test.sh` passes; `check.sh` (fast) ends "all checks passed". `check.sh --all` will fail until Task 6 adds `install-test.sh` and `security.sh` — that is expected now.

- [ ] **Step 4: Commit**

```bash
git add -A
git -c user.name=vladtara -c user.email=vlad@glaps.fun commit -m "ci: add check.sh orchestrator and eval schema test.sh"
```

---

### Task 6: Slow checks (security.sh, install-test.sh)

**Files:**
- Create: `scripts/security.sh`
- Create: `scripts/install-test.sh`

**Interfaces:**
- Consumes: `scripts/lib/common.sh`.
- Produces:
  - `scripts/security.sh [--staged]` — gitleaks secret scan; `--staged` scans staged changes (pre-commit), default scans full history.
  - `scripts/install-test.sh` — parses both marketplace catalogs and asserts every entry's source dir and `.claude-plugin/plugin.json` exist; completes the `check.sh --all` suite.

- [ ] **Step 1: Write `scripts/security.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/security.sh [--staged]

Scan for secrets with gitleaks.
  --staged    Scan staged changes only (fast; for pre-commit).
  (default)   Scan the full git history.
  -h, --help  Show this help.
EOF
}

staged=false
case "${1:-}" in
  --staged) staged=true ;;
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    log_error "unknown argument: $1"
    usage
    exit 2
    ;;
esac

cd "$REPO_ROOT"
skip_unless_tool gitleaks || exit 0

if "$staged"; then
  gitleaks protect --staged --redact --no-banner
else
  gitleaks detect --redact --no-banner
fi
log_ok "no secrets detected"
```

- [ ] **Step 2: Write `scripts/install-test.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/install-test.sh

Smoke-test the install contract: every plugin referenced by either marketplace
catalog must have its source directory and Claude manifest present on disk.
  -h, --help  Show this help.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    log_error "unknown argument: $1"
    usage
    exit 2
    ;;
esac

cd "$REPO_ROOT"
require_tool python3

python3 <<'PY'
import json
import sys
from pathlib import Path

catalogs = [
    Path(".claude-plugin/marketplace.json"),
    Path(".agents/plugins/marketplace.json"),
]

errors = []
checked = 0

for catalog in catalogs:
    if not catalog.exists():
        errors.append(f"{catalog}: missing marketplace catalog")
        continue
    try:
        data = json.loads(catalog.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"{catalog}: invalid JSON: {exc}")
        continue

    plugins = data.get("plugins")
    if not isinstance(plugins, list) or not plugins:
        errors.append(f"{catalog}: 'plugins' must be a non-empty array")
        continue

    for i, entry in enumerate(plugins):
        loc = f"{catalog} (plugins[{i}])"
        source = entry.get("source") if isinstance(entry, dict) else None
        if not isinstance(source, str) or not source.strip():
            errors.append(f"{loc}: missing 'source'")
            continue
        src_dir = Path(source[2:] if source.startswith("./") else source)
        if not src_dir.is_dir():
            errors.append(f"{loc}: source dir not found: {src_dir.as_posix()}")
            continue
        manifest = src_dir / ".claude-plugin" / "plugin.json"
        if not manifest.exists():
            errors.append(f"{loc}: manifest not found: {manifest.as_posix()}")
            continue
        checked += 1

if errors:
    for e in errors:
        print(f"::error::{e}")
    sys.exit(1)

print(f"Install smoke test passed for {checked} catalog entr(ies).")
PY
log_ok "install smoke test passed"
```

- [ ] **Step 3: Make executable and verify, including the full suite**

Run:
```bash
chmod +x scripts/security.sh scripts/install-test.sh
shellcheck scripts/security.sh scripts/install-test.sh
shfmt -i 2 -ci -bn -d scripts/security.sh scripts/install-test.sh
scripts/install-test.sh
scripts/security.sh
scripts/check.sh --all
```
Expected: shellcheck/shfmt silent; install-test passes; security reports no secrets; `check.sh --all` ends "all checks passed".

- [ ] **Step 4: Commit**

```bash
git add -A
git -c user.name=vladtara -c user.email=vlad@glaps.fun commit -m "ci: add security.sh and install-test.sh slow checks"
```

---

### Task 7: Pre-commit configuration and developer docs

**Files:**
- Create: `.pre-commit-config.yaml`
- Modify: `README.md` (add a Development section)

**Interfaces:**
- Consumes: `scripts/fmt.sh`, `scripts/lint.sh`, `scripts/validate.sh`, `scripts/security.sh`.
- Produces: pre-commit hooks that run the fast suite + staged secret scan via local hooks (no duplicated tool config).

- [ ] **Step 1: Write `.pre-commit-config.yaml`**

```yaml
repos:
  - repo: local
    hooks:
      - id: fmt-check
        name: format check (shfmt + prettier)
        entry: scripts/fmt.sh --check
        language: script
        pass_filenames: false
      - id: lint
        name: lint (shellcheck, yamllint, markdownlint, actionlint)
        entry: scripts/lint.sh
        language: script
        pass_filenames: false
      - id: validate
        name: validate (structure, marketplace, json, yaml, shell)
        entry: scripts/validate.sh --fast
        language: script
        pass_filenames: false
      - id: gitleaks
        name: secret scan (staged)
        entry: scripts/security.sh --staged
        language: script
        pass_filenames: false
```

- [ ] **Step 2: Add a Development section to `README.md`**

Insert this section (place it after the existing intro/install content; keep surrounding text intact):
```markdown
## Development

All developer commands are shell scripts under `scripts/`, runnable from the repo root.

```bash
scripts/bootstrap.sh          # install tooling (Homebrew on macOS)
pre-commit install            # enable git hooks (fast checks on commit)

scripts/fmt.sh                # auto-format shell/JSON/YAML
scripts/check.sh              # fast suite: fmt --check, lint, validate --fast
scripts/check.sh --all        # everything CI runs (adds links, tests, install, security)
```

Local checks call the same scripts CI runs, so passing `scripts/check.sh --all`
locally means the pipeline will pass too.
```

- [ ] **Step 3: Verify pre-commit runs the scripts**

Run:
```bash
scripts/lint.sh                # yamllint validates the new .pre-commit-config.yaml
pre-commit run --all-files
```
Expected: `scripts/lint.sh` exits 0; `pre-commit run --all-files` reports all four hooks Passed. (If pre-commit isn't installed, run `scripts/bootstrap.sh` first.)

- [ ] **Step 4: Commit**

```bash
git add .pre-commit-config.yaml README.md
git -c user.name=vladtara -c user.email=vlad@glaps.fun commit -m "ci: add pre-commit config and developer docs"
```

---

### Task 8: CI workflow (fast/slow jobs)

**Files:**
- Modify: `.github/workflows/ci.yml` (full rewrite to two parallel jobs)

**Interfaces:**
- Consumes: `scripts/bootstrap.sh --ci`, `scripts/fmt.sh`, `scripts/lint.sh`, `scripts/validate.sh`, `scripts/install-test.sh`, `scripts/security.sh`.
- Produces: a CI gate where both `fast` and `slow` jobs must pass.

- [ ] **Step 1: Replace `.github/workflows/ci.yml` entirely**

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  fast:
    name: Fast checks
    runs-on: ubuntu-latest
    env:
      CI: "true"
    steps:
      - uses: actions/checkout@v4
      - name: Install tooling
        run: scripts/bootstrap.sh --ci
      - name: Format check
        run: scripts/fmt.sh --check
      - name: Lint
        run: scripts/lint.sh
      - name: Validate (fast)
        run: scripts/validate.sh --fast

  slow:
    name: Slow checks
    runs-on: ubuntu-latest
    env:
      CI: "true"
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Install tooling
        run: scripts/bootstrap.sh --ci
      - name: Validate (slow)
        run: scripts/validate.sh --slow
      - name: Install smoke test
        run: scripts/install-test.sh
      - name: Secret scan
        run: scripts/security.sh
```

- [ ] **Step 2: Lint the workflow locally**

Run: `actionlint .github/workflows/ci.yml && scripts/lint.sh`
Expected: actionlint reports nothing; `scripts/lint.sh` exits 0.

- [ ] **Step 3: Commit and push to verify on a PR**

```bash
git add .github/workflows/ci.yml
git -c user.name=vladtara -c user.email=vlad@glaps.fun commit -m "ci: split CI into fast and slow jobs"
git push -u origin cicd-overhaul
```
Then open a PR and confirm both `Fast checks` and `Slow checks` jobs go green. Expected: both jobs pass; the commands match what `scripts/check.sh --all` runs locally.

---

### Task 9: Release tooling

**Files:**
- Create: `cliff.toml`
- Create: `scripts/release-dryrun.sh`
- Create: `.github/workflows/release.yml`
- Create: `docs/RELEASING.md`

**Interfaces:**
- Consumes: `scripts/check.sh --all`, git-cliff.
- Produces:
  - `scripts/release-dryrun.sh vX.Y.Z[-rc.N]` — preflight + changelog preview.
  - `release.yml` — on tag `v*`, runs the full gate, generates notes, publishes a Release.

- [ ] **Step 1: Write `cliff.toml`**

```toml
[changelog]
header = "# Changelog\n\n"
body = """
{% for group, commits in commits | group_by(attribute="group") %}
### {{ group | upper_first }}
{% for commit in commits %}
- {{ commit.message | upper_first }}\
{% endfor %}
{% endfor %}
"""
trim = true

[git]
conventional_commits = true
filter_unconventional = false
commit_parsers = [
  { message = "^feat", group = "Features" },
  { message = "^fix", group = "Bug Fixes" },
  { message = "^docs", group = "Documentation" },
  { message = "^ci", group = "CI/CD" },
  { message = "^chore", group = "Miscellaneous" },
  { message = ".*", group = "Other" },
]
tag_pattern = "v[0-9]*"
filter_commits = false
```

- [ ] **Step 2: Write `scripts/release-dryrun.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/release-dryrun.sh vX.Y.Z[-rc.N]

Preflight a release without publishing:
  - refuse on a dirty working tree
  - validate the tag is semver and does not already exist
  - run scripts/check.sh --all (the release gate)
  - preview the changelog git-cliff would generate
  -h, --help  Show this help.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "")
    log_error "a version tag is required, e.g. v1.2.0"
    usage
    exit 2
    ;;
esac

tag="$1"
cd "$REPO_ROOT"

if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]]; then
  log_error "tag '$tag' is not vX.Y.Z or vX.Y.Z-rc.N"
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  log_error "working tree is dirty; commit or stash before releasing"
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  log_error "tag '$tag' already exists"
  exit 1
fi

log_info "running release gate: scripts/check.sh --all"
"$SCRIPT_DIR/check.sh" --all

if [[ "$tag" == *-rc.* ]]; then
  log_info "classification: PRERELEASE"
else
  log_info "classification: stable release"
fi

if skip_unless_tool git-cliff; then
  log_info "changelog preview for $tag:"
  git-cliff --unreleased --tag "$tag"
fi

log_ok "dry-run complete; '$tag' is ready to tag and push"
```

- [ ] **Step 3: Write `.github/workflows/release.yml`**

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

permissions:
  contents: read

jobs:
  release:
    name: Publish release
    runs-on: ubuntu-latest
    permissions:
      contents: write
    env:
      CI: "true"
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install tooling
        run: scripts/bootstrap.sh --ci

      - name: Release gate
        run: scripts/check.sh --all

      - name: Generate changelog
        uses: orhun/git-cliff-action@v4
        with:
          config: cliff.toml
          args: --latest --strip header
        env:
          OUTPUT: CHANGELOG_NOTES.md

      - name: Publish GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ github.ref_name }}
        run: |
          prerelease=()
          if [[ "$TAG" == *-rc.* ]]; then
            prerelease=(--prerelease)
          fi
          gh release create "$TAG" \
            --title "$TAG" \
            --notes-file CHANGELOG_NOTES.md \
            "${prerelease[@]}"
```

- [ ] **Step 4: Write `docs/RELEASING.md`**

```markdown
# Releasing

Releases are repo-level semantic-version tags. Pushing a tag `vX.Y.Z`
(or `vX.Y.Z-rc.N` for a prerelease) triggers `.github/workflows/release.yml`,
which runs the full check suite, generates a changelog with git-cliff, and
publishes a GitHub Release.

## Cutting a release

1. Ensure `main` is green and checked out with a clean tree.
2. Dry-run: `scripts/release-dryrun.sh v1.2.0`
   (runs the full gate and previews the changelog).
3. Tag and push:
   ```bash
   git tag v1.2.0
   git push origin v1.2.0
   ```
4. Watch the Release workflow. On success, a GitHub Release appears.
   `-rc.N` tags are marked as prereleases automatically.

## Versioning

- `vMAJOR.MINOR.PATCH`. Adding a plugin or notable skill content → MINOR.
  Fixes/typos → PATCH. Breaking layout/manifest changes → MAJOR.
- Prereleases: `v1.2.0-rc.1`, `-rc.2`, … before the stable `v1.2.0`.

## Recovery / rollback

- **Bad release, not yet announced:** delete and redo.
  ```bash
  gh release delete v1.2.0 --yes
  git push --delete origin v1.2.0
  # fix, then re-tag
  ```
- **Already public:** never rewrite a published tag. Ship the next patch
  (`v1.2.1`) as the correction and note the regression in its release notes.
- **Workflow failed mid-run:** the tag exists but no Release was created.
  The workflow is idempotent (the only write is `gh release create`), so fix
  the cause and re-run the failed workflow from the Actions tab.
```

- [ ] **Step 5: Make executable and verify**

Run:
```bash
chmod +x scripts/release-dryrun.sh
shellcheck scripts/release-dryrun.sh
shfmt -i 2 -ci -bn -d scripts/release-dryrun.sh
actionlint .github/workflows/release.yml
scripts/release-dryrun.sh --help
scripts/lint.sh
```
Expected: shellcheck/shfmt/actionlint silent; `--help` prints usage; `scripts/lint.sh` exits 0 (it lints the new workflow YAML and RELEASING.md; `cliff.toml` has no linter and is exercised by the dry-run instead).

- [ ] **Step 6: Commit**

```bash
git add cliff.toml scripts/release-dryrun.sh .github/workflows/release.yml docs/RELEASING.md
git -c user.name=vladtara -c user.email=vlad@glaps.fun commit -m "feat: add tag-driven release workflow and dry-run"
```

---

### Task 10: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (Validation section + any `.ci/` references)

**Interfaces:**
- Consumes: the finished `scripts/` suite.
- Produces: documentation that matches the new layout.

- [ ] **Step 1: Replace the "Validation" section commands in `CLAUDE.md`**

Find the block listing the five `.ci/validate-*.sh` commands and replace it with:
```markdown
## Validation (the only "tests")

Run the full suite locally before committing — this is exactly what GitHub Actions runs:

```bash
scripts/check.sh          # fast: fmt --check, lint, validate --fast
scripts/check.sh --all    # full: also markdown links, eval tests, install smoke, secret scan
```

Individual stages live under `scripts/` (`fmt.sh`, `lint.sh`, `validate.sh`,
`test.sh`, `install-test.sh`, `security.sh`) and the underlying validators under
`scripts/checks/`. All validators operate on **git-tracked files only**
(`git ls-files`) — stage files before validating or you will get misleading passes.
```

- [ ] **Step 2: Update any remaining `.ci/` mentions**

Search and update: `grep -rn "\.ci/" CLAUDE.md README.md`. Replace any lingering `.ci/...` references with the `scripts/` equivalents. Expected after edits: `grep -rn "\.ci/" CLAUDE.md README.md` returns nothing.

- [ ] **Step 3: Verify and commit**

Run: `scripts/check.sh --all`
Expected: ends "all checks passed".
```bash
git add CLAUDE.md README.md
git -c user.name=vladtara -c user.email=vlad@glaps.fun commit -m "docs: point CLAUDE.md at scripts/ validation suite"
```

---

## Final verification

- [ ] `scripts/check.sh` exits 0.
- [ ] `scripts/check.sh --all` exits 0.
- [ ] `git ls-files .ci` returns nothing (directory removed).
- [ ] `shellcheck $(git ls-files '*.sh')` and `shfmt -i 2 -ci -bn -d $(git ls-files '*.sh')` are silent.
- [ ] CI `fast` and `slow` jobs both pass on the PR.
- [ ] `scripts/release-dryrun.sh v0.1.0` runs the gate and previews a changelog.
- [ ] No TOML/GoReleaser machinery exists anywhere in the tree.
