# Channel Manifest

A channel manifest is the preferred installer input. It points at the
architecture-specific bootstrap manifest and the shared runtime archive.

```json
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "aarch64",
    "nixSystem": "aarch64-linux"
  },
  "runtime": {
    "url": "nix-termux-runtime.tar.gz",
    "sha256": "<sha256>"
  },
  "bootstrapManifest": {
    "url": "nix-termux-bootstrap-aarch64.json"
  }
}
```

Set `NIX_TERMUX_CHANNEL_BASE_URL` before running the installer:

```sh
export NIX_TERMUX_CHANNEL_BASE_URL=https://example.invalid/releases/v0.1.0
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh" -o "$tmp_dir/install.sh"
curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh.sha256" -o "$tmp_dir/install.sh.sha256"
(cd "$tmp_dir" && sha256sum -c install.sh.sha256)
sh "$tmp_dir/install.sh"
```

The installer detects the Termux architecture with `dpkg --print-architecture`
and fetches `nix-termux-channel-$arch.json` from that base URL. Set
`NIX_TERMUX_ARCH` to override detection, or set `NIX_TERMUX_CHANNEL_URL` to use
an exact channel manifest URL.

The channel `platform.termuxArch` must match the detected or overridden Termux
architecture, and `platform.nixSystem` must be the corresponding Nix system.
The installer rejects mismatches before fetching runtime or bootstrap archives.

The installer resolves relative `runtime.url` and `bootstrapManifest.url`
against the channel URL, so mirrors can host all release files in one directory.
