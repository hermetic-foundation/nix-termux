# Release Process

`nix-termux` releases are ordinary GitHub releases. There is no required
project-specific deployment service.

## Build Locally

```sh
nix flake check
nix build .#installer
nix build .#runtime-archive
nix build .#bootstrap
```

The installer result contains:

```text
install.sh
install.sh.sha256
```

The runtime result contains:

```text
nix-termux-runtime.tar.gz
nix-termux-runtime.tar.gz.sha256
```

The bootstrap result contains:

```text
nix-termux-channel-<arch>.json
nix-termux-bootstrap-<arch>.tar.gz
nix-termux-bootstrap-<arch>.json
nix-termux-bootstrap-<arch>.registration
```

## Publish

Push a version tag:

```sh
jj bookmark move main --to @
jj git push --bookmark main
git tag v0.1.0
git push origin v0.1.0
```

The `ci` workflow builds `.#installer` and `.#runtime-archive` on x86_64, builds
`.#bootstrap` and `.#channel` on native x86_64 and aarch64 Linux runners,
writes `SHA256SUMS`, and attaches the result files to the GitHub release for
the tag.

## Artifact URL Shape

The preferred install entrypoint is the channel manifest:

```sh
export NIX_TERMUX_CHANNEL_BASE_URL=https://example.invalid/releases/v0.1.0
curl -L https://example.invalid/releases/v0.1.0/install.sh | sh
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
