# Defensive patterns

Treat every input as untrusted and every external command as able to fail. These patterns turn a script that works on the happy path into one that's safe to run unattended.

## Contents

- [Validate inputs early and loudly](#validate-inputs-early-and-loudly)
- [Clean up with `trap`](#clean-up-with-trap)
- [Iterate over files safely](#iterate-over-files-safely)
- [Guard destructive operations](#guard-destructive-operations)
- [Idempotency and retries](#idempotency-and-retries)
- [Handle secrets carefully](#handle-secrets-carefully)
- [Concurrency](#concurrency)

## Validate inputs early and loudly

Fail before doing work, with a message that says what was wrong.

```bash
# Require a variable to be set and non-empty, with a custom message.
: "${API_TOKEN:?API_TOKEN must be set}"

# Provide a default for an optional variable without tripping nounset.
log_level="${LOG_LEVEL:-info}"

# Validate a value against an allowed set.
case "${env}" in
  dev|staging|prod) ;;
  *) die "invalid environment: ${env} (expected dev|staging|prod)" ;;
esac

# Confirm a dependency exists before relying on it.
command -v jq >/dev/null 2>&1 || die "jq is required but not installed"

# Confirm a file is readable before reading it.
[[ -r "${config}" ]] || die "cannot read config: ${config}"
```

The `${VAR:?message}` form is the most concise guard against the unset-variable footgun that turns `rm -rf "${DIR}/"` into `rm -rf /`.

## Clean up with `trap`

A script that creates temp files, locks, or background processes must remove them on **every** exit path — success, error, and Ctrl-C. `trap` is how you guarantee that without scattering cleanup at every `return`.

```bash
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/script-name.XXXXXX")"
readonly work_dir

cleanup() {
  local rc=$?
  trap - EXIT                    # disable recursion before cleanup
  if ! rm -rf -- "${work_dir}"; then
    printf 'warning: failed to remove temporary directory: %s\n' "${work_dir}" >&2 || :
  fi
  exit "${rc}"
}
trap cleanup EXIT
trap 'exit 130' INT              # 128 + SIGINT(2)
trap 'exit 143' TERM             # 128 + SIGTERM(15)
```

`mktemp -d` creates a uniquely named directory with safe permissions, avoiding the predictable-path race conditions of `/tmp/myscript-$$`. Disable the `EXIT` trap before cleanup to avoid recursion, and run cleanup in an explicit conditional so `set -e` cannot abort the handler. Report cleanup failure, then exit with the saved status so it does not replace the original result.

## Iterate over files safely

Filenames may contain spaces, newlines, tabs, leading dashes, and glob characters. Two robust idioms; **never** `for f in $(ls)`.

```bash
# Globbing — simplest when matching by pattern in a directory.
shopt -s nullglob              # an empty match expands to nothing, not the literal pattern
for file in ./*.log; do
  process "${file}"
done

# NUL-delimited find — robust for recursion and arbitrary names.
while IFS= read -r -d '' file; do
  process "${file}"
done < <(find . -type f -name '*.log' -print0)
```

`IFS= read -r -d ''` reads up to a NUL byte (`-d ''`), disables backslash mangling (`-r`), and preserves leading/trailing whitespace (`IFS=`). The `-print0`/`-d ''` pairing is the only fully safe way to stream filenames.

Read a file line by line the same careful way:

```bash
while IFS= read -r line || [[ -n "${line}" ]]; do
  printf '%s\n' "${line}"
done < "${input}"
```

The `|| [[ -n "$line" ]]` keeps the last line even when the file lacks a trailing newline.

## Guard destructive operations

```bash
# Refuse to act on an unset/empty target.
target="${1:?target path required}"

# Anchor the path and use -- so a leading dash or glob can't reinterpret it.
rm -rf -- "${target:?}"

# Offer a dry-run for anything irreversible or remote.
# printf %q is Bash-only.
run() {
  if (( dry_run )); then
    printf 'DRY-RUN:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
  else
    "$@"
  fi
}
run rm -rf -- "${target}"
```

The `%q` formatter preserves Bash argument boundaries in a one-line diagnostic. POSIX `sh` has no equivalent shell-escaping formatter; use a fixed label and print each argument as data on its own labeled line instead of constructing a reusable command string.

For deletes within a base directory, validate that the resolved path stays inside the base before removing, so a `../` in input can't escape.

## Idempotency and retries

Automation reruns. Make operations safe to run twice, and make flaky network/IO operations retry with backoff.

```bash
mkdir -p "${dir}"                       # no error if it already exists
ln -sfn "${target}" "${link}"           # replace the symlink destination

retry() {
  local attempts="$1"; shift
  local n=1 delay=1
  until "$@"; do
    if (( n >= attempts )); then
      log_error "command failed after ${attempts} attempts: $*"
      return 1
    fi
    log_warn "attempt ${n} failed; retrying in ${delay}s"
    sleep "${delay}"
    (( n++, delay *= 2 ))
  done
}
retry 5 curl -fsS "${url}" -o "${dest}"
```

`ln -sfn` replaces an existing symlink destination, but the remove-and-create operation is not atomic.

`curl -f` makes HTTP errors return non-zero so `retry`/`pipefail` actually notice them.

## Handle secrets carefully

- Don't pass secrets as command-line arguments — they're visible in `ps` and shell history. Use environment variables or files with restricted permissions.
- Don't `echo`/`set -x` around secret handling; tracing prints values. Temporarily `set +x` around the sensitive block, or write to a `umask 077` file.
- Avoid here-strings/heredocs that bake secrets into the script; read them at runtime.

## Concurrency

When a script must not run twice at once (cron jobs, deploys), take a lock:

```bash
exec 9>"/var/lock/${SCRIPT_NAME}.lock"
flock -n 9 || die "another instance is already running"
```

`flock` releases automatically when the script exits and the descriptor closes. (Linux; on macOS use `shlock` or a `mkdir`-based lock, since `flock(1)` isn't in the base system.)
