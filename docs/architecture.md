# Architecture

`nix-termux` keeps stock Termux as the Android app and installs a small runtime
inside Termux home. This avoids depending on Termux app forks, Android package
identity changes, or a parallel add-on ecosystem.

## Runtime Layout

```text
$HOME/.nix-termux/
  bin/nix-termux
  etc/nix-termux.conf
  runtime/nix-termux.sh
  root/
  nix/
  share/installer/install.sh
  share/installer/uninstall.sh
```

The physical Nix store lives under:

```text
$HOME/.nix-termux/nix/store
```

The runtime enters a `proot` view with these key bindings:

```text
$HOME/.nix-termux/nix -> /nix
$HOME/.nix-termux/tmp -> /tmp
$HOME              -> /home/termux
$PREFIX           -> /termux
```

If `/sdcard` or `/storage` exist, the runtime binds them at the same absolute
paths so scripts that use Android shared storage continue to work. Set
`NIX_TERMUX_ANDROID_BIND_DIRS` to override that optional bind list.

Inside proot, the runtime exports stable XDG directories under
`/home/termux`: `.config`, `.cache`, `.local/share`, and `.local/state`.
It also exports `NIX_REMOTE=local`, `NIX_SSL_CERT_FILE`/`SSL_CERT_FILE`,
`NIX_PROFILES`, and a default `NIX_PATH=nixpkgs=flake:nixpkgs` so legacy
commands such as `nix-shell '<nixpkgs>'` work through the same flake-backed
nixpkgs reference as modern `nix run nixpkgs#...` commands. Set
`NIX_TERMUX_NIX_PATH` before invoking a wrapper to use a custom path.
When entering proot, the runtime creates `~/.nix-profile` as a symlink to the
Termux user profile if that path is not already present.
The proot PATH starts with `~/.nix-profile/bin`, then the default Nix profile,
then Termux and bootstrap system paths.

Before entering proot, the runtime writes `root/etc/resolv.conf` from
`$PREFIX/etc/resolv.conf`, host `/etc/resolv.conf`, or Android `getprop` DNS
values so Nix can resolve substituter and flake hosts.

## Wrapper Model

The installer writes wrappers into `$PREFIX/bin`:

```text
nix-termux
nix
nix-shell
nix-env
nix-store
nix-build
nix-channel
nix-collect-garbage
nix-copy-closure
nix-hash
nix-instantiate
nix-prefetch-url
```

Termux add-ons should use these normal Termux-visible commands. They do not
need to know about `proot` or the private state directory.

If one of those commands already exists in `$PREFIX/bin`, the installer stores a
copy under `$HOME/.nix-termux/share/prefix-backup/` before writing the wrapper.
`nix-termux uninstall` restores those backups and removes only managed wrappers.
It also removes the managed `~/.nix-profile` symlink when it still points at the
nix-termux Termux user profile.

## Runtime Archive

The standalone installer can fetch `nix-termux-runtime.tar.gz` through
`NIX_TERMUX_RUNTIME_ARCHIVE_URL`. That archive contains:

```text
bin/nix-termux
installer/install.sh
installer/uninstall.sh
runtime/nix-termux.sh
```

Running from a source checkout does not need this archive because the installer
can read those files directly.

## Channel Manifest

The preferred remote install path is `NIX_TERMUX_CHANNEL_URL`. A channel
manifest points to both the runtime archive and the architecture-specific
bootstrap manifest, reducing install setup to one URL.
The installed `nix-termux upgrade` command reruns the installer against the
saved or supplied channel and replaces the runtime files from the channel's
runtime archive before refreshing the bootstrap.

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
