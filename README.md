# nix-termux

`nix-termux` is an installer and runtime layer for running Nix inside stock
Termux. It is designed to keep Termux itself unchanged so existing Termux
add-ons keep using the real `com.termux` app and normal Termux scripts.

The runtime uses `proot` to present a virtual `/nix` while storing data under
Termux home. Bootstrap artifacts are configured by URL so users can mirror or
replace them without depending on project-specific deployment infrastructure.

## Status

This repository is at the first implementation stage. It provides:

- AGPLv3-or-later licensing from the first commit.
- A Nix flake and `direnv` entry with `use flake`.
- A stock-Termux installer skeleton.
- `nix-termux` runtime commands for `doctor`, `enter`, `run`, `env`, and
  `uninstall`.
- A versioned bootstrap manifest contract and host smoke test for the
  installer/wrapper path.

The bootstrap artifact format is intentionally simple and still needs real
Nix closure publishing before this is useful as an end-user installer.

## Development

```sh
direnv allow
nix flake check
shellcheck bin/nix-termux installer/*.sh runtime/*.sh
shfmt -w bin/nix-termux installer/*.sh runtime/*.sh
```

`nix flake check` runs shell formatting, ShellCheck, and a host smoke test that
installs a fake bootstrap archive into a temporary Termux-like prefix.

## Termux Install Shape

The intended install flow is:

```sh
pkg install proot curl tar xz coreutils
export NIX_TERMUX_BOOTSTRAP_MANIFEST_URL=https://example.invalid/nix-termux/bootstrap-aarch64.json
curl -L https://example.invalid/nix-termux/install.sh | sh
nix-termux doctor
```

The installer writes project files below:

```text
$HOME/.nix-termux
```

and exposes thin wrappers in:

```text
$PREFIX/bin
```

Those wrappers are what Termux add-ons should call. For example,
`Termux:Widget` can run a script that executes:

```sh
nix-termux run nixpkgs#hello
```

For local development or mirrored artifacts, the installer also accepts
`NIX_TERMUX_BOOTSTRAP_URL` and `NIX_TERMUX_BOOTSTRAP_SHA256` directly.

After installation, the saved manifest can be reused with:

```sh
nix-termux upgrade-bootstrap
```

or replaced explicitly:

```sh
nix-termux upgrade-bootstrap https://example.invalid/nix-termux/bootstrap-aarch64.json
```

## License

`nix-termux` is licensed under the GNU Affero General Public License version 3
or later. See `LICENSE`.
