---
name: bash-scripting
description: Expert guidance for writing, hardening, debugging, and reviewing Bash and POSIX shell scripts. Use whenever the user writes, edits, refactors, or pastes a .sh / .bash file or shell snippet; asks for a script, automation, wrapper, installer, backup, deploy, cron, CI/CD, or system-admin script; mentions shebang, set -euo pipefail, strict mode, ShellCheck (SC2086 etc.), shfmt, Bats, trap, getopts, IFS, here-doc, subshell, command substitution, exit codes, quoting, globbing, arrays, or parameter expansion; reports a shell script that fails, hangs, mis-parses arguments, breaks on spaces/special characters, or behaves differently on macOS vs Linux; or asks "why does my bash script…" or "is this shell script safe/portable". Trigger even when the user does not say the word "bash" but is clearly authoring or fixing shell code. Prefer this over generic answers for any non-trivial shell work.
---

# Bash Scripting

Use this skill to write, harden, debug, and review **Bash and POSIX shell** scripts to a production standard: scripts that fail loudly instead of silently, survive filenames with spaces and special characters, parse arguments predictably, clean up after themselves, and behave the same on a teammate's machine as on yours.

Shell behavior is **environment-sensitive**. The same script can pass on GNU/Linux and break on macOS (BSD userland), or work in Bash 5 and fail in Bash 3.2 (still the default `/bin/bash` on macOS), or break the moment it runs under `/bin/sh` (dash) instead of bash. So before giving version- or platform-specific advice, establish what shell, version, and OS the script actually targets — don't assume the user's machine matches yours.

## First step

When writing or reviewing anything beyond a one-liner, check the toolchain and target so your advice matches reality:

```bash
bash scripts/bash-version-check.sh
```

This reports the bash version, OS/userland (GNU vs BSD), and whether ShellCheck, shfmt, and Bats are installed — which determines what you can actually run versus only recommend. If the script is destined for a different target (a container, a CI runner, `/bin/sh`), say which assumptions your answer uses and recommend verifying there.

## Decide the target shell first

The single most important decision is **which interpreter the script runs under**, because it determines what syntax is legal:

- **`#!/usr/bin/env bash`** — the default for new scripts. Lets you use arrays, `[[ ]]`, `local`, process substitution, and parameter-expansion case operators. `env` finds bash on `PATH` (important on macOS, where a modern bash is usually under Homebrew, not `/bin`).
- **`#!/bin/sh`** — only when POSIX portability is a hard requirement (Alpine images, BSD base systems, init scripts). Many bash features are unavailable here; see `references/05-portability-posix.md`.

If the user hasn't said, ask or infer from context (a Dockerfile `FROM alpine` strongly implies `sh`; a developer laptop script implies bash). Don't write bash-only syntax into a `#!/bin/sh` script — that's the most common portability bug.

## Use strict mode for standalone execution

Bash's defaults are forgiving to a fault: it ignores unset variables, marches past failed commands, and hides failures in the middle of a pipeline. Strict mode turns those silent failures into loud ones, which is what you want in automation:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -Eeuo pipefail
  initialize_runtime
  install_traps
  main "$@"
fi
```

- `-e` (errexit) — exit on any unhandled non-zero command, instead of continuing in a broken state.
- `-u` (nounset) — treat use of an unset variable as an error, catching typos and missing arguments.
- `-o pipefail` — a pipeline fails if **any** stage fails, not just the last; without it `false | true` "succeeds".
- `-E` (errtrace) — makes an installed `ERR` trap inherit into functions, command substitutions, and subshell environments. It does not affect `EXIT` cleanup traps.

Standalone executables should enable `set -Eeuo pipefail` inside the direct-execution guard, immediately before their runtime initialization and `main` path. A file that can be sourced must only define functions at import time: do not change the caller's shell options, `IFS`, traps, or runtime globals. Expose explicit initialization and trap-installation functions instead.

`set -e` has real sharp edges: it does not fire in condition contexts such as `if` or the tested parts of `&&`/`||`, and modern non-POSIX Bash clears `errexit` inside command substitutions unless `inherit_errexit` is enabled. It's a safety net, not a substitute for explicit error handling. See `references/01-strict-mode-and-structure.md` for the gotchas and the script skeleton.

**Don't hand-write the skeleton from scratch — generate it:**

```bash
bash scripts/bash-scaffold.sh --name deploy --description "Deploy the app" > deploy.sh
```

This emits a ready-to-edit script with direct-execution-only strict mode and initialization, a `usage()`/`--help`, a manual `while`/`case` long-option parser, leveled logging to stderr, a `trap`-based cleanup handler, and a `main "$@"` guard — the same structure this skill recommends, so you start correct instead of refactoring toward correct.

## Task routing

Read the reference file that matches the task. Each is a focused deep-dive so you load only what you need:

- **Strict mode details, script structure, functions, logging, `main` guard, exit codes** → `references/01-strict-mode-and-structure.md`
- **Defensive patterns: input validation, `trap`/cleanup, `mktemp`, dry-run, idempotency, retries, NUL-safe file handling, avoiding `rm -rf` footguns** → `references/02-defensive-patterns.md`
- **Quoting, word-splitting, globbing, parameter expansion, arrays, `[[ ]]` tests, command substitution, here-docs** → `references/03-quoting-expansion-arrays.md`
- **Debugging (`set -x`, `trap DEBUG`, `BASH_XTRACEFD`), ShellCheck, shfmt, and Bats testing** → `references/04-debugging-and-testing.md`
- **POSIX `sh` portability and GNU-vs-BSD (macOS) tool differences** → `references/05-portability-posix.md`
- **Authoritative external docs (Bash manual, ShellCheck wiki, Bats)** → run `bash scripts/bash-doc-discover.sh`

## Always lint before declaring a script done

A script that "runs on my machine" is not finished. The single highest-leverage habit in shell scripting is running a static analyzer, because the most dangerous bugs (unquoted expansions that break on spaces, `cd` failures that aren't checked, masked exit codes) are invisible until the wrong input hits them in production.

After writing or editing any script, run the bundled linter, which chooses a `bash -n`, `sh -n`, or `dash -n` syntax parser from the shebang, then runs ShellCheck and `shfmt -d` when available:

```bash
bash scripts/bash-lint.sh path/to/script.sh
```

Treat ShellCheck findings as the default source of truth. When you suppress one with `# shellcheck disable=SCxxxx`, add a comment explaining *why* the warning doesn't apply here — a bare disable is a future bug waiting to be re-enabled. Look up any code at `https://www.shellcheck.net/wiki/SCxxxx`.

## Core operating rules

These apply to essentially every script; the references explain the why in depth.

**Quote every expansion** unless you have a specific, deliberate reason not to. `"$var"`, `"$@"`, `"${array[@]}"`, `"$(cmd)"`. Unquoted expansions undergo word-splitting and glob expansion, so a path with a space or a `*` silently turns into multiple arguments. This is the number-one shell bug, and `"$@"` (never the bare `$*`) is how you forward arguments without mangling them.

**Send errors and diagnostics to stderr, data to stdout.** Anything a caller might parse goes to stdout; warnings, progress, and errors go to stderr (`>&2`). This keeps `script | other-tool` clean and lets users separate logs from output.

**Prefer `printf` over `echo`.** `echo`'s handling of `-n`, `-e`, and backslashes varies across shells and platforms; `printf '%s\n' "$x"` is predictable everywhere.

**Use `$(...)`, never backticks**, and `[[ ]]` for tests in bash (it doesn't word-split, supports `=~` regex and `&&`). Reserve `[ ]`/`test` for `#!/bin/sh`.

**Never parse `ls`, and don't `for f in $(ls)`.** Filenames can contain spaces, newlines, and globs. Iterate with globs (`for f in ./*.txt`) or NUL-delimited `find … -print0 | while IFS= read -r -d '' f`. See `references/02-defensive-patterns.md`.

**Guard destructive operations.** Quote and anchor paths (`rm -rf -- "${dir:?dir is unset}"/`), refuse to run on empty variables, and offer a `--dry-run` for anything that deletes, overwrites, or mutates remote/system state. A `rm -rf "$DIR/"` where `$DIR` is unset becomes `rm -rf /`.

**Put logic in functions and gate execution.** Keep a `main()` and run it only when the file is executed, not sourced, so scripts stay testable:

```bash
main() { ... }
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

## Reviewing or hardening an existing script

When the user hands you a script to review or fix, work in this order — it surfaces the highest-severity issues first:

1. **Run the linter** (`scripts/bash-lint.sh`) and read every finding. Don't eyeball what a tool can prove.
2. **Check the header**: correct shebang for the target shell, strict mode present, and whether `set -e` assumptions actually hold.
3. **Scan for the classic footguns**: unquoted `$var`, `$(ls)`/`for … in $(…)`, unguarded `cd` (use `cd … || exit`), unquoted destructive paths, missing `--` before user-supplied filenames, temp files in `/tmp` without `mktemp`, secrets in argv or `echo`.
4. **Trace error paths**: what happens on failure mid-script? Is there cleanup? Are exit codes meaningful?
5. **Question portability** only against the stated target — don't "fix" bash-isms in a script that's correctly `#!/usr/bin/env bash`.

Explain each change and *why it matters* rather than just rewriting silently, so the user learns the pattern and can apply it next time. When you propose a fix, prefer the smallest change that removes the hazard over a wholesale rewrite, unless the user asked for a rewrite.

## Debugging a failing script

Reproduce before theorizing. Re-run with tracing to see exactly what executed:

```bash
bash -x ./script.sh        # trace every command after expansion
bash -n ./script.sh        # syntax-check without running
```

For long scripts, narrow the trace with `set -x` / `set +x` around the suspect region, or set `PS4='+ ${BASH_SOURCE}:${LINENO}: '` to get file:line prefixes. A `trap 'echo "failed at line $LINENO" >&2' ERR` pinpoints where errexit fired. Full debugging workflow in `references/04-debugging-and-testing.md`.
