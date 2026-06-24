# Release Process

`nix-termux` releases are ordinary GitHub releases. There is no required
project-specific deployment service.

## Build Locally

```sh
nix flake check
nix build .#installer
nix build .#runtime-archive
nix build .#bootstrap
nix build .#channel
nix build .#release
```

The release result is a complete hostable directory for the current system's
Termux architecture:

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

The individual `.#installer`, `.#runtime-archive`, `.#bootstrap`, and
`.#channel` packages remain available when a release pipeline wants separate
artifacts.

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

The `ci` workflow builds `.#release` on native x86_64 and aarch64 Linux
runners, merges the bundles, rejects conflicting duplicate common artifacts,
recomputes `SHA256SUMS`, and attaches the result files to the GitHub release
for the tag.

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
