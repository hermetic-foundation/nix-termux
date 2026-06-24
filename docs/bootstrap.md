# Bootstrap Contract

`nix-termux` installs the runtime and wrappers independently from the bootstrap
archive. The archive is the only part that needs to contain Nix binaries and a
seed store.

## Archive Layout

The archive must unpack directly into `$NIX_TERMUX_STATE_DIR`, normally
`$HOME/.nix-termux`, and provide:

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
root/etc/nix/nix.conf
root/etc/passwd
root/etc/group
root/etc/nsswitch.conf
root/etc/hosts
root/etc/hostname
root/root/
root/bin/sh
root/usr/bin/env
nix-termux/bootstrap.registration
```

`root/` is the `proot` root filesystem. The runtime bind-mounts `nix/` to
`/nix`, Termux home to `/home/termux`, and the Termux prefix to `/termux`.
The root filesystem must define a `termux` user and group in `root/etc/passwd`
and `root/etc/group` so tools that inspect user identity work inside proot.
It must also include `root/etc/hosts`, `root/etc/hostname`, and
`root/etc/nsswitch.conf` so basic hostname and resolver lookups behave
predictably before networked Nix commands run.

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
    "url": "https://example.invalid/nix-termux/bootstrap-aarch64.tar.gz",
    "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
  },
  "layout": {
    "storeDir": "nix",
    "rootDir": "root",
    "nixBin": "nix/var/nix/profiles/default/bin/nix",
    "registration": "nix-termux/bootstrap.registration"
  }
}
```

Set `NIX_TERMUX_BOOTSTRAP_MANIFEST_URL` before running the installer:

```sh
export NIX_TERMUX_BOOTSTRAP_MANIFEST_URL=https://example.invalid/nix-termux/bootstrap-aarch64.json
export NIX_TERMUX_CHANNEL_BASE_URL=https://example.invalid/nix-termux
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh" -o "$tmp_dir/install.sh"
curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh.sha256" -o "$tmp_dir/install.sh.sha256"
(cd "$tmp_dir" && sha256sum -c install.sh.sha256)
sh "$tmp_dir/install.sh"
```

The manifest `platform.termuxArch` must match the detected or overridden Termux
architecture. The installer rejects mismatches before fetching or unpacking the
bootstrap archive.

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
registration file is included in the archive and emitted beside it so the
installer can register the seed closure with Nix's local database during
bootstrap activation.
