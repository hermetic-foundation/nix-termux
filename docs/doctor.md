# Doctor

`nix-termux doctor` checks whether the Termux runtime, `proot`, bootstrap store,
Nix default profile, Termux user profile layout, home profile path, CA bundle,
resolver config, wrapper commands, and activation metadata are present.

```sh
nix-termux doctor
```

For scripts, use JSON output:

```sh
nix-termux doctor --json
```

The JSON shape is stable for schema version 1 of the runtime:

```json
{
  "schemaVersion": 1,
  "runtimeVersion": "0.1.0",
  "installedRuntimeVersion": "0.1.0",
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
  }
}
```

`ok` is `false` if any required check fails. The command exits non-zero in that
case, even for JSON output.
