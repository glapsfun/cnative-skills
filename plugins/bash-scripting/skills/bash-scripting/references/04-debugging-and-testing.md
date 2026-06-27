# Debugging, linting, and testing

## Contents

- [Debugging](#debugging)
- [Linting with ShellCheck](#linting-with-shellcheck)
- [Formatting with shfmt](#formatting-with-shfmt)
- [Testing with Bats](#testing-with-bats)
- [Testing the bundled helpers](#testing-the-bundled-helpers)
- [Suggested CI gate](#suggested-ci-gate)

## Debugging

Reproduce the failure under tracing before forming a theory.

```bash
bash -n script.sh        # parse only: catch syntax errors without executing
bash -x script.sh        # xtrace: print every command after expansion, prefixed with +
bash -u script.sh        # treat unset variables as errors for this run
```

Trace only the region you suspect, so output stays readable:

```bash
set -x          # turn tracing on
suspect_function "$@"
set +x          # turn it back off
```

Make the trace tell you *where* you are. The default `+` prefix is uninformative; this adds file and line:

```bash
export PS4='+ ${BASH_SOURCE[0]}:${LINENO}:${FUNCNAME[0]:-main}: '
```

Pinpoint where `errexit` fired with an `ERR` trap (needs `set -E` to fire inside functions):

```bash
set -Eeuo pipefail
trap 'echo "ERROR: exit $? at ${BASH_SOURCE[0]}:${LINENO} (${BASH_COMMAND})" >&2' ERR
```

Send xtrace to its own file descriptor so it doesn't pollute the script's stderr:

```bash
exec 5>/tmp/trace.log
export BASH_XTRACEFD=5
set -x
```

`BASH_XTRACEFD` requires Bash 4.1+. On stock macOS Bash 3.2, omit it and let xtrace use stderr, redirecting the script's stderr externally if a separate trace file is needed.

Common bug-to-cause map:

| Symptom | Likely cause |
|---------|--------------|
| "unbound variable" exit | `set -u` plus a typo or unset optional var — use `${var:-default}`. |
| Breaks on a filename with a space | An unquoted `$var` / `$(…)` / `$@`. Quote it. |
| Pipeline reports success despite a failed stage | Missing `set -o pipefail`. |
| `cd` failed but script kept going into the wrong dir | Unchecked `cd` — write `cd "$d" \|\| exit`. |
| Works on Linux, fails on macOS | GNU vs BSD tool flags, or bash 3.2 — see `05-portability-posix.md`. |
| `local x=$(cmd)` never fails even when `cmd` does | `local` masks exit status — split into `local x; x=$(cmd)`. |
| Loop body's variable changes vanish after the loop | The loop ran in a subshell (right side of a pipe). Use process substitution `< <(…)`. |

## Linting with ShellCheck

ShellCheck is the highest-value tool in shell development — it statically catches the bugs that only surface with the wrong input. Run it on everything; the bundled `scripts/bash-lint.sh` chooses a `bash -n`, `sh -n`, or `dash -n` syntax parser from the shebang, then runs ShellCheck and `shfmt -d` when available.

```bash
shellcheck script.sh
shellcheck -s bash script.sh          # force the bash dialect
shellcheck -x script.sh               # follow `source`d files
```

High-frequency codes worth recognizing (full text at `https://www.shellcheck.net/wiki/SCxxxx`):

- **SC2086** — unquoted variable, subject to word-splitting/globbing. The most common real bug. Quote it.
- **SC2046** — unquoted `$(…)` splits on whitespace. Quote or restructure.
- **SC2155** — `local x=$(cmd)` masks the command's exit status. Declare then assign.
- **SC2164** — `cd` without `|| exit`; a failed `cd` lets the script run in the wrong directory.
- **SC2034** — variable assigned but never used (often a typo elsewhere).
- **SC2068** — unquoted `$@`/array expansion. Use `"$@"` / `"${arr[@]}"`.
- **SC2207** — capturing command output into an array via unquoted `$(…)`. Use `mapfile`.

When a warning genuinely doesn't apply, suppress it *with a reason*:

```bash
# shellcheck disable=SC2016  # single quotes are intentional; awk needs the literal $1
awk '{ print $1 }' "${file}"
```

Per-directory config lives in `.shellcheckrc` (e.g. `disable=SC2059`, `source-path=SCRIPTDIR`).

## Formatting with shfmt

`shfmt` is the gofmt of shell — consistent, diffable formatting so reviews focus on logic, not whitespace.

```bash
shfmt -d script.sh           # show diff (what would change); non-zero exit if not formatted
shfmt -w script.sh           # write changes in place
shfmt -i 2 -ci -bn -w .      # 2-space indent, indent case bodies, binary ops at line start
```

Wire `shfmt -d` into CI to fail on unformatted code.

## Testing with Bats

[Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System) gives shell scripts real unit tests. Each `@test` block runs in isolation; `run` captures `$status` and `$output`.

```bash
#!/usr/bin/env bats

setup() {
  # Source the script without executing main (thanks to the BASH_SOURCE guard).
  source "${BATS_TEST_DIRNAME}/../script.sh"
  TEST_TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "${TEST_TMP}"
}

@test "to_upper converts to uppercase" {
  run to_upper "hello"
  [ "$status" -eq 0 ]
  [ "$output" = "HELLO" ]
}

@test "fails with clear message when arg is missing" {
  run my_script            # invoking with no args
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing required argument"* ]]
}
```

Run with `bats test/` (or `bats test/*.bats`). The `setup`/`teardown` pair gives each test a fresh temp dir. Designing scripts with a `main "$@"` source-guard (see `01-strict-mode-and-structure.md`) is what makes individual functions testable like this.

For quick assertions without Bats, a plain script using the same `run`-style checks works too — but Bats gives you TAP output, isolation, and CI integration for free.

## Testing the bundled helpers

After changing this skill's helper scripts, run the regression harness from the skill directory:

```bash
bash evals/test-helpers.sh
```

The harness covers scaffold syntax, source safety, direct-execution initialization, signal exits, one-line escaped logging and dry-run output, linter discovery and dialect selection, fail-closed linter errors, unusual pathnames, helper argument validation, and the current POSIX documentation URL. It requires no optional lint/test tools or network access.

## Suggested CI gate

A minimal pipeline that keeps shell quality from regressing:

1. `bash -n` on every script (syntax).
2. `shellcheck` on every script (correctness) — fail on any finding.
3. `shfmt -d` (formatting) — fail if anything would change.
4. `bats test/` (behavior).

The bundled `scripts/bash-lint.sh` runs steps 1–3 when those tools are installed, but it intentionally skips missing ShellCheck or shfmt. CI must install both and assert `command -v shellcheck` and `command -v shfmt` before running the wrapper, or invoke `shellcheck` and `shfmt -d` directly. Add Bats as step 4.
