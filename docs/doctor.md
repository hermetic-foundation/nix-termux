# Doctor

`nix-termux doctor` checks whether the Termux runtime, `proot`, bootstrap store,
Nix profile, CA bundle, and activation metadata are present.

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
  "ok": true,
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
  "nixConf": {
    "ok": true,
    "path": "/data/data/com.termux/files/home/.nix-termux/root/etc/nix/nix.conf"
  },
  "certs": {
    "ok": true,
    "path": "/data/data/com.termux/files/home/.nix-termux/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt"
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
