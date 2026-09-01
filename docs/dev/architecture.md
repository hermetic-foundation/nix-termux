# Architecture

## System Model

`nix-termux` is a runtime installed into stock Termux. It does not build or
replace the Android application.

```text
Termux command or add-on
        |
        v
$PREFIX/bin/nix wrapper
        |
        v
nix-termux exec nix ...
        |
        v
PRoot with a virtual /nix
        |
        v
single-user Nix from nixpkgs
```

## Components

| Component | Responsibility |
| --- | --- |
| `installer/install.sh` | Fetch, validate, activate, and write wrappers |
| `runtime/nix-termux.sh` | Build the PRoot environment and dispatch commands |
| `bootstrap/` | Produce the initial Nix closure and local store database |
| `channel/` | Connect one runtime archive to one platform bootstrap |
| `release/` | Assemble a directory suitable for ordinary HTTP hosting |

## Installed State

The default state directory is `$HOME/.nix-termux`:

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

The physical store is `$HOME/.nix-termux/nix/store`.

## PRoot View

The runtime creates these primary bindings:

| Termux path | Guest path |
| --- | --- |
| `$HOME/.nix-termux/nix` | `/nix` |
| `$HOME/.nix-termux/tmp` | `/tmp` |
| `$HOME` | `/home/termux` |
| `$PREFIX` | `/termux` |
| `/dev`, `/proc`, `/sys` | Same path |

`/sdcard` and `/storage` are bound when present. Set
`NIX_TERMUX_ANDROID_BIND_DIRS` to replace that optional list.

PRoot starts in `/home/termux`. The outer Termux working directory is not
currently translated or preserved.

## Guest Environment

| Variable | Value or source |
| --- | --- |
| `HOME` | `/home/termux` |
| `NIX_CONF_DIR` | `/etc/nix` |
| `NIX_REMOTE` | `local` |
| `NIX_PATH` | `nixpkgs=flake:nixpkgs` by default |
| `NIX_PROFILES` | Default and Termux user profiles |
| `NIX_SSL_CERT_FILE` | Bootstrap CA bundle |
| `SHELL` | Bootstrap Bash by default |
| `GC_NPROCS` | Termux `nproc`, an explicit override, or `1` |

XDG config, cache, data, and state directories live below `/home/termux`.

The guest `PATH` is:

```text
/home/termux/.nix-profile/bin
/nix/var/nix/profiles/default/bin
/usr/bin
/bin
```

## Entry Sequence

1. Validate Termux paths, state, and PRoot availability.
2. Create writable home, profile, state, and temporary directories.
3. Refresh `root/etc/resolv.conf` from Termux, Android, or host DNS data.
4. Resolve `GC_NPROCS` without reading Android's restricted `/proc/stat`.
5. Remove Termux's inherited `LD_PRELOAD`.
6. Execute PRoot with the bindings and guest environment.
7. Run the requested command or an interactive login shell.

Removing `LD_PRELOAD` prevents `termux-exec` from rewriting guest paths such as
`/usr/bin/env` before PRoot receives them.

## Wrapper Model

The installer writes these managed commands into `$PREFIX/bin`:

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

Each Nix wrapper delegates to `nix-termux exec <wrapper-name>`. Arguments remain
unchanged.

An existing command is backed up below
`$HOME/.nix-termux/share/prefix-backup`. Uninstall restores only backups owned
by nix-termux.

## Install and Upgrade

A standalone installer obtains two inputs through a channel manifest:

1. A shared runtime archive containing scripts and tools.
2. An architecture-specific bootstrap manifest and archive.

The default remote is the latest GitHub release. Exact channels, mirrors, and
direct artifact URLs remain available as explicit overrides.

`nix-termux upgrade` reruns the saved installer with the saved or supplied
channel URL. Bootstrap registration is loaded into the local Nix store before
the staged files become active.

## Runtime Boundaries

- Nix uses a local single-user store.
- The Nix daemon and build users are disabled.
- Build sandboxing is disabled.
- PRoot emulates paths and identity; it does not grant kernel privileges.
- NixOS boot, service, and system activation do not apply on Android.

See the [user limitations](../user/limitations.md) for user-visible effects.
