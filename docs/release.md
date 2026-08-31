# Release Process

`nix-termux` releases are ordinary GitHub releases. There is no required
project-specific deployment service.

## Build Locally

```sh
nix flake check
nix build .#installer
nix build .#runtime-archive
nix build .#bootstrap-aarch64
nix build .#channel-aarch64
nix build .#release-aarch64
```

The `release-aarch64` result is a complete hostable directory for physical
Android devices. It is assembled with host tools and can be built on x86_64
Linux:

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

The native `.#release`, `.#bootstrap`, and `.#channel` outputs remain available
for the current host architecture. The additive `.#bootstrap-aarch64` and
`.#channel-aarch64` outputs expose the cross-built pieces separately when a
release pipeline does not want the complete bundle.

Release validation checks the standalone `install.sh.sha256` file used by the
install snippets, the standalone `nix-termux-runtime.tar.gz.sha256` file used by
mirrors, and the aggregate `SHA256SUMS` manifest. The standalone checksum files
must name their exact targets, and each bootstrap `.registration` sidecar must
match the `nix-termux/bootstrap.registration` file inside its bootstrap archive.

## Publish

Push a version tag:

```sh
jj bookmark move main --to @
jj git push --bookmark main
git tag v0.1.0
git push origin v0.1.0
```

The release workflow builds `.#release-aarch64`, validates all checksum files
and manifest relationships, and attaches the result files to the GitHub
release for the tag. The build does not require an aarch64 runner.

## Artifact URL Shape

The preferred install entrypoint is the channel manifest:

```sh
export NIX_TERMUX_CHANNEL_BASE_URL=https://example.invalid/releases/v0.1.0
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh" -o "$tmp_dir/install.sh"
curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh.sha256" -o "$tmp_dir/install.sh.sha256"
(cd "$tmp_dir" && sha256sum -c install.sh.sha256)
sh "$tmp_dir/install.sh"
```

The channel manifest points to the runtime archive and the bootstrap manifest.
Relative URLs are resolved against `NIX_TERMUX_CHANNEL_URL`.

Release manifests can refer to archives beside the manifest:

```json
{
  "archive": {
    "url": "nix-termux-bootstrap-aarch64.tar.gz"
  }
}
```

The installer resolves relative archive URLs against
`NIX_TERMUX_BOOTSTRAP_MANIFEST_URL`, so users and mirrors can host the manifest
and archive together without modifying the archive hash.

The standalone installer also needs the runtime archive when it is not run from
a source checkout or existing installation:

```sh
export NIX_TERMUX_RUNTIME_ARCHIVE_URL=https://example.invalid/nix-termux-runtime.tar.gz
export NIX_TERMUX_RUNTIME_ARCHIVE_SHA256=<sha256>
```
