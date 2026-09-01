# Troubleshooting

## Run Doctor

Start with:

```sh
nix-termux doctor
```

Every required component is reported as `ok` or `missing`. The command exits
nonzero when any required check fails.

Use JSON in scripts or bug reports:

```sh
nix-termux doctor --json
```

The JSON document uses schema version `1`. It reports runtime, Termux, PRoot,
store, profile, certificate, DNS, wrapper, bootstrap activation, and
configuration flake status.
See the [doctor JSON contract](../dev/doctor.md) for the complete shape.

## PRoot Is Missing

Install the Termux package:

```sh
pkg install -y proot
```

Then rerun `nix-termux doctor`.

## Configuration Evaluation Fails

The runtime stops before the requested command when the configuration flake is
invalid or unlocked.

Evaluate it with activation disabled:

```sh
NIX_TERMUX_CONFIG_FLAKE=none \
  nix-termux exec nix flake check \
  path:/home/termux/.config/nix-termux
```

Compare it with the installed template when recovery is required:

```sh
diff -u \
  ~/.nix-termux/share/config/flake.nix \
  ~/.config/nix-termux/flake.nix
```

See [configuration](configuration.md) for the output contract and escape
hatches.

## Nix Uses the Wrong Project

The wrapper currently starts in `/home/termux`. Enter the environment before
selecting a local project:

```sh
nix-termux enter
cd ~/src/my-project
nix build .
```

## A Store Symlink Looks Broken

Paths such as `result` and `~/.nix-profile` point into `/nix`. Inspect or use
them from inside the environment:

```sh
nix-termux enter
readlink -f result
```

## DNS Fails

Check the generated resolver file:

```sh
nix-termux exec cat /etc/resolv.conf
```

Rerun the wrapper after the Android network changes. The runtime refreshes the
resolver configuration on every entry.

## The `/proc/stat` GC Warning Appears

Update the runtime and start a new PRoot session:

```sh
nix-termux upgrade
exit
nix --version
```

The runtime sets `GC_NPROCS` from Termux's `nproc`. Override it only for
diagnosis:

```sh
GC_NPROCS=1 nix --version
```

## Collect Diagnostic Output

```sh
nix-termux doctor --json
nix-termux env
nix --version
```

Do not include credentials, private channel URLs, or unrelated environment
variables in a public report.
