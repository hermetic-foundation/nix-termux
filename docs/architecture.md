# Architecture

`nix-termux` keeps stock Termux as the Android app and installs a small runtime
inside Termux home. This avoids depending on Termux app forks, Android package
identity changes, or a parallel add-on ecosystem.

## Runtime Layout

```text
$HOME/.nix-termux/
  bin/nix-termux
  runtime/nix-termux.sh
  root/
  nix/
  share/installer/uninstall.sh
```

The physical Nix store lives under:

```text
$HOME/.nix-termux/nix/store
```

The runtime enters a `proot` view that binds this directory as:

```text
/nix
```

## Wrapper Model

The installer writes wrappers into `$PREFIX/bin`:

```text
nix-termux
nix
nix-shell
nix-env
nix-store
nix-build
```

Termux add-ons should use these normal Termux-visible commands. They do not
need to know about `proot` or the private state directory.

## Bootstrap Model

Bootstrap artifacts are fetched when `NIX_TERMUX_BOOTSTRAP_MANIFEST_URL` or
`NIX_TERMUX_BOOTSTRAP_URL` is set. The archive unpacks into
`$HOME/.nix-termux` and provides at least:

```text
nix/store
nix/var/nix/profiles/default/bin/nix
root/usr/bin/env
```

The manifest schema lives at `bootstrap/manifest.schema.json`.
