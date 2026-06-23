# Bootstrap Contract

`nix-termux` installs the runtime and wrappers independently from the bootstrap
archive. The archive is the only part that needs to contain Nix binaries and a
seed store.

## Archive Layout

The archive must unpack directly into `$NIX_TERMUX_STATE_DIR`, normally
`$HOME/.nix-termux`, and provide:

```text
nix/store/
nix/var/nix/profiles/default/bin/nix
root/usr/bin/env
```

`root/` is the `proot` root filesystem. The runtime bind-mounts `nix/` to
`/nix`, Termux home to `/home/termux`, and the Termux prefix to `/termux`.

## Manifest

Bootstrap manifests use schema version 1 and are validated by
`bootstrap/manifest.schema.json`.

```json
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "aarch64",
    "nixSystem": "aarch64-linux"
  },
  "archive": {
    "url": "https://example.invalid/nix-termux/bootstrap-aarch64.tar",
    "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
  },
  "layout": {
    "storeDir": "nix",
    "rootDir": "root",
    "nixBin": "nix/var/nix/profiles/default/bin/nix"
  }
}
```

Set `NIX_TERMUX_BOOTSTRAP_MANIFEST_URL` before running the installer:

```sh
export NIX_TERMUX_BOOTSTRAP_MANIFEST_URL=https://example.invalid/nix-termux/bootstrap-aarch64.json
curl -L https://example.invalid/nix-termux/install.sh | sh
```

Direct `NIX_TERMUX_BOOTSTRAP_URL` and `NIX_TERMUX_BOOTSTRAP_SHA256` values are
still supported and override manifest archive fields when set.

## Building Artifacts

Build the bootstrap artifact for the current system with:

```sh
nix build .#bootstrap
```

The output directory contains:

```text
nix-termux-bootstrap-<arch>.tar.gz
nix-termux-bootstrap-<arch>.json
nix-termux-bootstrap-<arch>.registration
```

The tarball contains the closure needed by the default profile. The
registration file is emitted beside it so future installer work can register
the seed closure with Nix's local database during bootstrap activation.
