# Release Process

## Release Model

Releases are ordinary GitHub releases. Every release is also a directory that
can be copied to any static HTTP host.

The standalone installer defaults to:

```text
https://github.com/hermetic-foundation/nix-termux/releases/latest/download
```

Pinned versions and mirrors use the same artifact layout.

## Build

Run the host suite and build all release components:

```sh
nix flake check -L
nix build .#installer
nix build .#runtime-archive
nix build .#bootstrap-aarch64
nix build .#channel-aarch64
nix build .#release-aarch64
```

`release-aarch64` is the complete physical-device directory. It can be built
on x86_64 Linux.

## Artifact Layout

```text
install.sh
install.sh.sha256
nix-termux-runtime.tar.gz
nix-termux-runtime.tar.gz.sha256
nix-termux-channel-<arch>.json
nix-termux-bootstrap-<arch>.tar.gz
nix-termux-bootstrap-<arch>.json
nix-termux-bootstrap-<arch>.registration
SHA256SUMS
```

Native `release`, `bootstrap`, and `channel` outputs target the build host.
Their `*-aarch64` counterparts produce physical-device artifacts.

## Validate

```sh
tools/serve-release.sh --check result
```

Release validation requires:

- `install.sh.sha256` to name exactly `install.sh`
- `nix-termux-runtime.tar.gz.sha256` to name its exact archive
- `SHA256SUMS` to cover every published artifact
- Each bootstrap registration sidecar to match the archived registration
- Channel and bootstrap platform values to agree
- Runtime and bootstrap archives to contain the required files and modes

## Version

Update the version in every component covered by
`tests/smoke/version-consistency.sh`. Run the full flake check after the change.

Use a semantic version tag prefixed with `v`, such as `v0.1.0`.

## Publish

Fetch and publish `main` before creating the tag:

```sh
jj git fetch --remote origin
jj rebase -s @ -o main@origin
jj bookmark move main --to @
jj git push --bookmark main --remote origin
```

Create and push the release tag:

```sh
jj tag set v0.1.0 -r main
jj git push --tag v0.1.0 --remote origin
```

The tag starts `.github/workflows/release.yml`. The workflow:

1. Runs the shared release preflight.
2. Builds `.#release-aarch64`.
3. Verifies all checksum and manifest relationships.
4. Attaches every file to the GitHub release.

The workflow does not require an ARM64 runner.

## Verify Published URLs

After the workflow completes, check both pinned and latest entry points:

```sh
curl -fIL https://github.com/hermetic-foundation/nix-termux/releases/download/v0.1.0/install.sh
curl -fIL https://github.com/hermetic-foundation/nix-termux/releases/latest/download/install.sh
```

Run the [physical-device acceptance test](device-validation.md) against the
published release before announcing it.

## Mirror

Copy the complete release directory to one HTTP directory. Relative manifest
URLs keep runtime and bootstrap artifacts colocated.

Validate the copied directory before serving it:

```sh
tools/serve-release.sh --check /path/to/mirror-directory
```

Users select the mirror with `NIX_TERMUX_CHANNEL_BASE_URL`. No
project-specific deployment service is required.
