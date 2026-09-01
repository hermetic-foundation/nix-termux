# Channel Contract

## Purpose

A channel manifest selects one shared runtime archive and one
architecture-specific bootstrap manifest.

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

The JSON Schema is `channel/schema.json`.

## Channel Discovery

The standalone installer discovers a channel in this order:

1. `NIX_TERMUX_CHANNEL_URL`, when set.
2. `NIX_TERMUX_CHANNEL_BASE_URL` plus the detected architecture filename.
3. The canonical latest GitHub release when no channel or artifact override is
   present.

The canonical base URL is:

```text
https://github.com/hermetic-foundation/nix-termux/releases/latest/download
```

Source-checkout installation does not apply the canonical default. It reads
runtime files from the checkout.

Direct runtime and bootstrap variables bypass or override the corresponding
fields discovered through a channel. They are intended for tests, mirrors, and
other controlled deployments.

## Architecture Mapping

The installer prefers `dpkg --print-architecture` and falls back to `uname`.

| Termux architecture | Nix system |
| --- | --- |
| `aarch64` | `aarch64-linux` |
| `arm` | `armv7l-linux` |
| `i686` | `i686-linux` |
| `x86_64` | `x86_64-linux` |

The manifest values must match the detected pair. A mismatch fails before an
archive is unpacked.

## URL Resolution

Relative `runtime.url` and `bootstrapManifest.url` values resolve beside the
channel manifest. Relative bootstrap archive URLs resolve beside the bootstrap
manifest.

An HTTP mirror can therefore copy a complete release directory without
rewriting JSON.

## Explicit Overrides

| Variable | Effect |
| --- | --- |
| `NIX_TERMUX_ARCH` | Override architecture detection |
| `NIX_TERMUX_CHANNEL_URL` | Select an exact channel manifest |
| `NIX_TERMUX_CHANNEL_BASE_URL` | Select a release or mirror directory |
| `NIX_TERMUX_RUNTIME_ARCHIVE_URL` | Override the channel runtime archive |
| `NIX_TERMUX_RUNTIME_ARCHIVE_SHA256` | Verify the direct runtime archive |
| `NIX_TERMUX_BOOTSTRAP_MANIFEST_URL` | Override the bootstrap manifest |
| `NIX_TERMUX_BOOTSTRAP_URL` | Override the bootstrap archive |
| `NIX_TERMUX_BOOTSTRAP_SHA256` | Verify the direct bootstrap archive |

Use the [user installation guide](../user/install.md) for pinned and mirrored
commands.

## Upgrade Behavior

Installation saves the resolved channel URL. `nix-termux upgrade` uses that
exact channel unless the user supplies another URL.

The runtime archive hash comes from the channel manifest. The bootstrap archive
hash comes from the bootstrap manifest.
