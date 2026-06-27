# Bash Scripting Skill Remediation Design

## Goal

Correct every finding from the `bash-scripting` skill review and add executable regression coverage so the bundled helpers cannot silently regress.

## Scope

Change only `plugins/bash-scripting` and its README description if user-facing behavior changes require it. Do not modify repository-wide CI validators.

## Root causes

1. The scaffold applies shell options, `IFS`, and signal traps before its direct-execution guard, so sourcing it mutates the caller.
2. The scaffold combines a newline-first `IFS` with `$*`, splitting multi-argument log and dry-run messages across lines.
3. The linter assumes Bash syntax for every target and discovers only `*.sh` files, despite claiming Bash and POSIX shell coverage.
4. The portability reference contains unverified GNU/BSD equivalence claims.
5. The existing evals describe desired answers but do not execute the bundled helpers.
6. Read-only helpers document a closed argument interface but silently accept unexpected arguments.

## Design

### Source-safe scaffold

Keep function definitions inert when the generated script is sourced. Apply strict mode and install traps only in the direct-execution path immediately before `main "$@"`.

Do not set global `IFS`. Rely on quoted expansions and command-local `IFS` assignments. Keep cleanup registration explicit so a script that does not allocate resources can remove it.

Format log arguments with repeated `printf` calls instead of `$*`. Render dry-run commands with Bash `%q` quoting so the displayed command preserves argument boundaries.

### Dialect-aware linter

Discover `*.sh`, `*.bash`, and executable extensionless files with a Bash, `sh`, or Dash shebang. Continue accepting explicitly supplied regular files regardless of their extension.

Choose the syntax parser from the shebang:

- Bash shebang or unknown dialect: `bash -n`
- POSIX `sh`: `sh -n`
- Dash: `dash -n` when available, otherwise `sh -n`

Keep ShellCheck as the semantic portability check. When it is unavailable or explicitly skipped, report that portability was not checked instead of claiming an unconditional quality pass.

### Portability guidance

Replace the non-portable `mktemp -t prefix` advice with an explicit `XXXXXX` template under `${TMPDIR:-/tmp}`. Replace the incorrect empty-input `xargs -0` claim with `find ... -exec ... {} +`. Correct `grealink` to `greadlink` and point documentation discovery at POSIX.1-2024 Issue 8.

### Helper interfaces

Make `bash-doc-discover.sh` and `bash-version-check.sh` reject unexpected arguments with exit status 2 and an error on stderr. Preserve `-h` and `--help`.

### Skill and eval guidance

Update `SKILL.md` and the relevant references so strict mode and traps are recommended for standalone execution without mutating callers when sourced. Correct the scaffold description to say it uses manual long-option parsing.

Update prose eval expectations to require source safety and conditional cleanup rather than unconditional traps.

Add `evals/test-helpers.sh` as a dependency-free regression harness. It will run helpers in isolated subprocesses and assert:

- Generated output parses as Bash.
- Sourcing generated output does not change shell options, `IFS`, or traps.
- Multi-argument logging remains on one line.
- Dry-run output preserves argument boundaries.
- Unexpected helper arguments fail with status 2.
- Directory lint discovery includes `.sh`, `.bash`, and extensionless shebang scripts.
- POSIX targets use a POSIX parser and do not receive an unconditional success claim when portability checks are skipped.
- Documentation output contains the current POSIX Issue 8 URL.

## Error handling

Regression tests must fail with a focused assertion message and leave temporary files behind only when cleanup itself fails. Helper usage errors must write diagnostics to stderr and return status 2.

## Non-goals

- Replacing ShellCheck, shfmt, or Bats.
- Making every Bash construct portable to POSIX `sh`.
- Refactoring repository-wide CI scripts.
- Adding network-dependent tests.

## Acceptance criteria

1. The new regression harness fails against the pre-fix helpers for the reviewed behaviors.
2. The harness passes after implementation.
3. `quick_validate.py` passes for the skill.
4. All repository structure, marketplace, JSON, Markdown-link, and shell-syntax validators pass.
5. ShellCheck and shfmt pass for every bundled helper and the new test harness.
6. The worktree contains only intentional remediation and design changes.
