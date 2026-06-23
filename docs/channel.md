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
curl -L https://example.invalid/install.sh | sh
```

The installer detects the Termux architecture with `pkg --print-architecture`
and fetches `nix-termux-channel-$arch.json` from that base URL. Set
`NIX_TERMUX_ARCH` to override detection, or set `NIX_TERMUX_CHANNEL_URL` to use
an exact channel manifest URL.

The installer resolves relative `runtime.url` and `bootstrapManifest.url`
against the channel URL, so mirrors can host all release files in one directory.
