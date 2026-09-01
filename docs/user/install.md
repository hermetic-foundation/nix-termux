# Install nix-termux

## Requirements

- An `aarch64` Android device
- Stock Termux from GitHub or F-Droid
- A working internet connection
- Enough free space for the Nix bootstrap and installed packages

Use the same distribution source for Termux and all Termux add-ons. Android
rejects add-ons signed by a different source.

> [!NOTE]
> If the release URL returns `404`, a public release has not been published yet.
> Developers can build and serve a release by following the
> [device validation guide](../dev/device-validation.md).

## Quick Install

Install the required Termux packages:

```sh
pkg update
pkg install -y proot curl tar xz-utils coreutils
```

Download and run the latest installer:

```sh
installer="$TMPDIR/nix-termux-install.sh"
curl -fL https://github.com/hermetic-foundation/nix-termux/releases/latest/download/install.sh -o "$installer"
sh "$installer"
rm -f "$installer"
```

The standalone installer defaults to the latest Hermetic Foundation release.
It verifies the runtime and bootstrap hashes from their manifests.

Installation also creates:

```text
~/.config/nix-termux/flake.nix
~/.config/nix-termux/flake.lock
```

These files control the Nix registry and binary caches. See the
[configuration guide](configuration.md).

## Verify the Installer

Use the checksum sidecar before running the installer when transport integrity
must be checked explicitly:

```sh
base=https://github.com/hermetic-foundation/nix-termux/releases/latest/download
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
curl -fL "$base/install.sh" -o "$tmp_dir/install.sh"
curl -fL "$base/install.sh.sha256" -o "$tmp_dir/install.sh.sha256"
(cd "$tmp_dir" && sha256sum -c install.sh.sha256)
sh "$tmp_dir/install.sh"
```

The checksum detects an incomplete or mismatched download. It does not replace
trust in the release host.

## Check the Result

```sh
nix-termux doctor
nix --version
nix run nixpkgs#hello
```

The final command downloads from `nixpkgs` and `cache.nixos.org`.

## Install a Pinned Release

Set the release directory before running its installer:

```sh
base=https://github.com/hermetic-foundation/nix-termux/releases/download/v0.1.0
curl -fL "$base/install.sh" -o "$TMPDIR/nix-termux-install.sh"
NIX_TERMUX_CHANNEL_BASE_URL="$base" sh "$TMPDIR/nix-termux-install.sh"
rm -f "$TMPDIR/nix-termux-install.sh"
```

Replace `v0.1.0` with the required release tag.

## Install from a Mirror

A mirror can host the files from a release directory without modification:

```sh
base=https://mirror.example/nix-termux/v0.1.0
curl -fL "$base/install.sh" -o "$TMPDIR/nix-termux-install.sh"
NIX_TERMUX_CHANNEL_BASE_URL="$base" sh "$TMPDIR/nix-termux-install.sh"
rm -f "$TMPDIR/nix-termux-install.sh"
```

Advanced deployments can set an exact `NIX_TERMUX_CHANNEL_URL`, runtime archive
URL, or bootstrap manifest URL. See the
[channel contract](../dev/channel.md) for precedence and validation.

## Update

Update from the channel saved during installation:

```sh
nix-termux upgrade
```

Switch to another channel:

```sh
nix-termux upgrade https://mirror.example/nix-termux/nix-termux-channel-aarch64.json
```

## Remove

```sh
nix-termux uninstall
```

The uninstaller removes managed files and restores Termux commands backed up
during installation. It preserves `~/.config/nix-termux` for later installs.
