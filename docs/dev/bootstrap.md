# Bootstrap Contract

## Purpose

The bootstrap archive contains the first Nix executable, its closure, and the
metadata required to initialize the local store. Runtime scripts are packaged
separately.

## Archive Layout

The archive unpacks directly into `$NIX_TERMUX_STATE_DIR`. The default is
`$HOME/.nix-termux`.

Required paths:

```text
nix/store/
nix/var/log/nix/drvs/
nix/var/nix/db/
nix/var/nix/gcroots/auto/
nix/var/nix/profiles/default/bin/nix
nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt
nix/var/nix/profiles/per-user/root/
nix/var/nix/profiles/per-user/termux/
nix/var/nix/temproots/
nix-termux/bootstrap.registration
root/bin/sh
root/etc/group
root/etc/hostname
root/etc/hosts
root/etc/nix/nix.conf
root/etc/nsswitch.conf
root/etc/passwd
root/root/
root/usr/bin/env
```

`root/` is the PRoot root filesystem. It must provide:

- A `termux` user and group
- Basic hostname and resolver files
- A shell and `/usr/bin/env`
- Nix configuration for local single-user operation

## Manifest Schema

Bootstrap manifests use schema version `1`. The JSON Schema is
`bootstrap/manifest.schema.json`.

```json
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "aarch64",
    "nixSystem": "aarch64-linux"
  },
  "archive": {
    "url": "nix-termux-bootstrap-aarch64.tar.gz",
    "sha256": "<sha256>"
  },
  "layout": {
    "storeDir": "nix",
    "rootDir": "root",
    "nixBin": "nix/var/nix/profiles/default/bin/nix",
    "registration": "nix-termux/bootstrap.registration"
  }
}
```

## Installer Validation

Before extraction or activation, the installer checks:

1. Schema version and required fields.
2. Termux architecture and Nix system agreement.
3. Exact supported layout values.
4. A lowercase SHA-256 archive hash.
5. Archive members for absolute paths and parent traversal.
6. Required files in the staging directory.
7. Store registration through the staged Nix executable.

Relative archive URLs resolve beside the bootstrap manifest. This allows a
release directory to move without regenerating archive hashes.

`NIX_TERMUX_BOOTSTRAP_URL` and `NIX_TERMUX_BOOTSTRAP_SHA256` override the
manifest archive fields when both are supplied intentionally.

## Build Outputs

Build the native bootstrap:

```sh
nix build .#bootstrap
```

Build the physical-device bootstrap from an x86_64 host:

```sh
nix build .#bootstrap-aarch64
```

The output contains:

```text
nix-termux-bootstrap-<arch>.tar.gz
nix-termux-bootstrap-<arch>.json
nix-termux-bootstrap-<arch>.registration
```

The registration sidecar must match
`nix-termux/bootstrap.registration` inside the archive.
