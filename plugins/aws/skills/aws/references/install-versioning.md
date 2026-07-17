# Install, Update, Pin, and Migrate

Content verified against AWS CLI v2 (baseline 2.36.1, July 2026). Always confirm with `aws --version`.

## v1 vs v2: which line are you on?

`aws --version` prints `aws-cli/2.x.y` or `aws-cli/1.x.y`.

- **v2** is the current major version, distributed only as a bundled installer (embedded Python — no separate Python needed). All new features land here.
- **v1** is in maintenance mode with an announced end-of-support; AWS recommends migrating to v2. It is a Python package (pip-installable) and shares the same `aws` command name — an old v1 on `$PATH` can shadow a new v2 install (`which -a aws`).
- Support policy: [AWS SDKs and tools maintenance policy](https://docs.aws.amazon.com/sdkref/latest/guide/maint-policy.html) and the [v1 end-of-support announcement](https://aws.amazon.com/blogs/developer/cli-v1-maintenance-mode-announcement/).

## Installing v2 (official distribution points only)

AWS supports only its own artifacts plus the official snap. Third-party repos (Homebrew, apt, dnf) are unofficial and may lag — fine for convenience, but say so.

**Linux x86_64** (ARM: swap `x86_64` → `aarch64`):

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip
sudo ./aws/install                    # → /usr/local/aws-cli, symlink in /usr/local/bin
```

Update in place: rerun with `sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update` (and `unzip -u` to skip overwrite prompts). On Amazon Linux, first `sudo yum remove awscli` to drop the preinstalled v1.

**macOS**: `curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o AWSCLIV2.pkg && sudo installer -pkg AWSCLIV2.pkg -target /`. Supported on macOS 11+ (2.21.0+).

**Windows**: `msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi` (all users, admin) or `AWSCLIV2-User.msi` (current user, no admin). `/qn` for silent.

**Snap** (official, auto-updating — cannot pin): `sudo snap install aws-cli --classic`.

**Docker**: official images `public.ecr.aws/aws-cli/aws-cli` (also on Docker Hub `amazon/aws-cli`); tag = CLI version, so pinning is just an image tag.

**GPG verification**: every `.zip` has a `.sig` (`same-url.zip.sig`); verify with the AWS CLI Team public key (fingerprint `FB5D B77F D5C1 18B8 0511 ADA8 A631 0ACC 4672 475C`) via `gpg --verify awscliv2.sig awscliv2.zip`. The "not certified with a trusted signature" warning is expected.

## Pinning a specific version

Append `-<version>` to the artifact filename — this is the supported pinning mechanism:

| Platform | Pinned URL pattern |
|---|---|
| Linux x86_64 | `https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.36.1.zip` |
| Linux ARM | `https://awscli.amazonaws.com/awscli-exe-linux-aarch64-2.36.1.zip` |
| macOS | `https://awscli.amazonaws.com/AWSCLIV2-2.36.1.pkg` |
| Windows | `https://awscli.amazonaws.com/AWSCLIV2-2.36.1.msi` |

Version list: the [v2 changelog](https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst). The installer does not auto-update — pin by baking the versioned URL into your image/CI bootstrap. Snap cannot pin; use the installer where teams need version control.

## Updating

- Installer-managed installs: download the new artifact and rerun `./aws/install --update` (or the pkg/msi again).
- **2.36.0+** ships a native `aws update` command that downloads and installs the latest version — convenient for interactive machines, but avoid it where versions must stay pinned.
- Uninstall: remove `/usr/local/aws-cli` and the `/usr/local/bin/aws{,_completer}` symlinks (Linux/macOS), or Add/Remove Programs on Windows.

## v1 → v2 breaking changes (script killers first)

- **Pager on by default**: v2 pipes all output through `less`/`more`, which hangs non-interactive jobs. Fix: `--no-cli-pager`, `cli_pager=` in config, or `AWS_PAGER=""`.
- **Binary params are base64 by default**: v2 treats blob inputs/outputs as base64 strings (v1 mixed raw/base64). Revert per-command with `--cli-binary-format raw-in-base64-out` or the `cli_binary_format` config setting. Classic symptom: `kms decrypt`/`lambda invoke` payloads that worked in v1 now fail or double-encode.
- **`ecr get-login` removed**: use `aws ecr get-login-password | docker login --username AWS --password-stdin <registry>`.
- **Timestamps normalized to ISO 8601** (v1 returned whatever the service sent). Revert with `cli_timestamp_format = wire`.
- **No URL fetching for parameters**: `http(s)://` values are passed literally; download with `curl` and use `file://` instead (`cli_follow_urlparam` removed).
- **CloudFormation empty changesets succeed**: `aws cloudformation deploy` with no changes exits 0 in v2 (v1 failed); `--fail-on-empty-changeset` restores v1 behavior.
- **Regional endpoints by default**: STS calls go to the regional endpoint, and S3 in `us-east-1` uses `s3.us-east-1.amazonaws.com` (use region `aws-global` to force the global endpoint).
- **S3**: SigV4 only (presigned URLs max 7 days); multipart copies now propagate tags/metadata (`--copy-props` to change); 2.23.0+ uses CRC64NVME upload checksums by default (`--checksum-algorithm` to override).
- **Return codes expanded**: 252/253/254 added and applied consistently — scripts that only checked `!= 0` are fine, scripts matching specific codes need review.
- Removed: hidden parameter aliases, `api_versions` config; plugin support is provisional (`[plugins]` + `cli_legacy_plugin_path`) — pin your version if you depend on it.

Full list: <https://docs.aws.amazon.com/cli/latest/userguide/cliv2-migration-changes.html>

## v2-only features worth knowing

`aws configure sso` / IAM Identity Center auth, auto-prompt (`--cli-auto-prompt`), wizards (`aws <service> wizard`), `aws configure import` (console CSV), `aws configure list-profiles`, `aws logs tail`, high-level `ddb put`/`ddb select`, `yaml`/`yaml-stream` output, client-side pager, official Docker images.
