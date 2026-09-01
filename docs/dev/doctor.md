# Doctor JSON Contract

## Command

`nix-termux doctor --json` exposes runtime readiness for scripts, add-ons, and
test automation:

```sh
nix-termux doctor --json
```

The command exits nonzero when any required component fails, even when it
successfully prints JSON.

## Schema Version 1

```json
{
  "schemaVersion": 1,
  "runtimeVersion": "0.1.1",
  "installedRuntimeVersion": "0.1.1",
  "ok": true,
  "config": {
    "path": "/data/data/com.termux/files/home/.nix-termux/etc/nix-termux.conf",
    "channelUrl": "https://example.invalid/nix-termux/nix-termux-channel-aarch64.json",
    "runtimeArchiveSha256": "<sha256>",
    "bootstrapManifestUrl": "https://example.invalid/nix-termux/nix-termux-bootstrap-aarch64.json"
  },
  "termux": {
    "ok": true,
    "prefix": "/data/data/com.termux/files/usr",
    "home": "/data/data/com.termux/files/home"
  },
  "proot": {
    "ok": true,
    "command": "proot"
  },
  "store": {
    "ok": true,
    "path": "/data/data/com.termux/files/home/.nix-termux/nix/store"
  },
  "nix": {
    "ok": true,
    "path": "/data/data/com.termux/files/home/.nix-termux/nix/var/nix/profiles/default/bin/nix"
  },
  "userProfile": {
    "ok": true,
    "path": "/data/data/com.termux/files/home/.nix-termux/nix/var/nix/profiles/per-user/termux/profile"
  },
  "homeProfile": {
    "ok": true,
    "path": "/data/data/com.termux/files/home/.nix-profile"
  },
  "nixConf": {
    "ok": true,
    "path": "/data/data/com.termux/files/home/.nix-termux/root/etc/nix/nix.conf"
  },
  "certs": {
    "ok": true,
    "path": "/data/data/com.termux/files/home/.nix-termux/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt"
  },
  "dns": {
    "ok": true,
    "path": "/data/data/com.termux/files/home/.nix-termux/root/etc/resolv.conf"
  },
  "wrappers": {
    "ok": true,
    "directory": "/data/data/com.termux/files/usr/bin",
    "missing": ""
  },
  "activation": {
    "ok": true,
    "path": "/data/data/com.termux/files/home/.nix-termux/etc/bootstrap-activation.conf",
    "bootstrapSha256": "<sha256>"
  },
  "configurationActivation": {
    "ok": true,
    "path": "/data/data/com.termux/files/home/.nix-termux/runtime/activate-config.sh"
  },
  "configurationFlake": {
    "ok": true,
    "path": "/data/data/com.termux/files/home/.config/nix-termux",
    "reference": "/home/termux/.config/nix-termux"
  }
}
```

## Top-Level Fields

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Version of this JSON contract |
| `runtimeVersion` | Version implemented by the running script |
| `installedRuntimeVersion` | Version recorded during installation |
| `ok` | Conjunction of all required readiness checks |
| `config` | Saved channel and artifact metadata |

Each component object contains an `ok` field and the paths or command values
needed to diagnose that component.

`configurationActivation` checks the managed runtime helper.
`configurationFlake` requires readable `flake.nix` and `flake.lock` files.

Adding fields within schema version `1` must remain backward compatible.
Removing or changing existing field types requires a new schema version.
