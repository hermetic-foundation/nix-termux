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

The installer currently accepts direct `NIX_TERMUX_BOOTSTRAP_URL` and
`NIX_TERMUX_BOOTSTRAP_SHA256` values. Manifest-driven install is the next step
once real artifacts are published.
