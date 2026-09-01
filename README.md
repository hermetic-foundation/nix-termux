# nix-termux

Run the Nix package manager inside stock Termux. No custom APK, Termux fork, or
Android plugin is required.

`nix-termux` keeps its Nix store in Termux home and uses PRoot to expose it as
`/nix`. Existing Termux add-ons continue to use the normal `com.termux` app.

## Install

The current Android target is `aarch64`. It has been tested with the Termux
`0.118.3` GitHub build on Android 16.

Run these commands in Termux:

```sh
pkg update
pkg install -y proot curl tar xz-utils coreutils resolv-conf
installer="$TMPDIR/nix-termux-install.sh"
curl -fL https://github.com/hermetic-foundation/nix-termux/releases/latest/download/install.sh -o "$installer"
sh "$installer"
rm -f "$installer"
```

The installer selects the channel for the device architecture and verifies the
runtime and bootstrap archives before unpacking them. It also creates a locked
configuration flake at `~/.config/nix-termux`.

Check the installation:

```sh
nix-termux doctor
nix run nixpkgs#hello
```

See the [installation guide](docs/user/install.md) for checksum verification,
pinned releases, mirrors, updates, and removal.

## Use Nix

Normal Nix commands are available through Termux wrappers:

```sh
nix run nixpkgs#ripgrep -- --version
nix shell nixpkgs#git -c git --version
nix profile install nixpkgs#jq
nix-termux exec jq --version
```

Registry and binary-cache settings are declared in
`~/.config/nix-termux/flake.nix`. Changes apply to the next command without
generating files in `~/.config/nix`.

Enter the environment before working on a local project:

```sh
nix-termux enter
cd ~/src/my-project
nix develop
```

Nix programs run inside the PRoot environment. A program installed with
`nix profile` is available through `nix-termux enter` or `nix-termux exec`.

## Termux Add-ons

Termux:Widget and similar add-ons can call the wrappers from ordinary Termux
scripts:

```sh
#!/data/data/com.termux/files/usr/bin/sh
nix-termux run nixpkgs#hello
```

Install Termux and its add-ons from the same source so their Android signatures
remain compatible.

## Current Boundaries

- Nix runs in single-user mode with a local store.
- Build sandboxing and the Nix daemon are disabled.
- NixOS activation and systemd services are not supported.
- Nix-installed programs must run inside the PRoot environment.
- Local source builds can encounter Android or PRoot kernel limitations.

See [current limitations](docs/user/limitations.md) for the tested surface and
known workflow gaps.

## Documentation

- [User guide](docs/user/README.md)
- [Installation](docs/user/install.md)
- [Usage](docs/user/usage.md)
- [Configuration](docs/user/configuration.md)
- [Troubleshooting](docs/user/troubleshooting.md)
- [Contributing](CONTRIBUTING.md)

## License

`nix-termux` is licensed under the GNU Affero General Public License version 3
or later. See [LICENSE](LICENSE).
