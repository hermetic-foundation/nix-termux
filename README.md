# nix-termux

`nix-termux` is an installer and runtime layer for running Nix inside stock
Termux. It is designed to keep Termux itself unchanged so existing Termux
add-ons keep using the real `com.termux` app and normal Termux scripts.

The runtime uses `proot` to present a virtual `/nix` while storing data under
Termux home. Bootstrap artifacts are configured by URL so users can mirror or
replace them without depending on project-specific deployment infrastructure.

## Status

This repository provides:

- AGPLv3-or-later licensing from the first commit.
- A Nix flake and `direnv` entry with `use flake`.
- A stock-Termux installer/runtime that keeps the normal Termux app in place.
- `nix-termux` runtime commands for `doctor`, `enter`, `run`, `env`,
  `smoke-test`, `upgrade`, `upgrade-bootstrap`, `version`, and `uninstall`.
- A versioned bootstrap manifest contract and host smoke test for the
  installer/wrapper path.
- A Nix-built bootstrap artifact package and GitHub release workflow for
  x86_64 and aarch64 bootstrap archives.
- A packaged real-device smoke test for validating releases inside Termux.

The remaining high-risk work is real-device validation on Termux/Android.

## Development

```sh
direnv allow
nix flake check
shellcheck bin/nix-termux installer/*.sh runtime/*.sh
shfmt -w bin/nix-termux installer/*.sh runtime/*.sh
```

`nix flake check` runs shell formatting, ShellCheck, and a host smoke test that
installs a fake bootstrap archive into a temporary Termux-like prefix.

Build local release artifacts with:

```sh
nix build .#installer
nix build .#runtime-archive
nix build .#bootstrap
nix build .#release
```

The release result is a hostable directory containing:

```text
install.sh
install.sh.sha256
nix-termux-runtime.tar.gz
nix-termux-runtime.tar.gz.sha256
nix-termux-channel-<arch>.json
nix-termux-bootstrap-<arch>.tar.gz
nix-termux-bootstrap-<arch>.json
nix-termux-bootstrap-<arch>.registration
SHA256SUMS
```

Tagged GitHub releases build and attach those artifacts through
`.github/workflows/ci.yml`.

Real Android support should be accepted with the on-device smoke test documented
in `docs/device-validation.md`:

```sh
sh "$HOME/.nix-termux/share/tests/device-smoke.sh"
```

or through the installed runtime command:

```sh
nix-termux smoke-test
```

Host-side validation helpers are available in a source checkout and in the Nix
package under `share/nix-termux/tools/`.

For emulator validation, build a release and use an existing Android Virtual
Device plus a stock Termux APK:

```sh
nix build .#release
tools/emulator-validate.sh --avd nix-termux-api-35 --termux-apk ~/Downloads/termux.apk --network
```

The helper serves the release to the emulator through `10.0.2.2`, stages the
Termux-side smoke script with `adb`, and keeps the local server running while
you execute the printed command inside Termux.

## Termux Install Shape

The intended install flow is:

```sh
pkg install proot curl tar xz coreutils
export NIX_TERMUX_CHANNEL_BASE_URL=https://example.invalid/nix-termux
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh" -o "$tmp_dir/install.sh"
curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh.sha256" -o "$tmp_dir/install.sh.sha256"
(cd "$tmp_dir" && sha256sum -c install.sh.sha256)
sh "$tmp_dir/install.sh"
nix-termux doctor
```

For scripts and Termux add-ons, `doctor` also has machine-readable output:

```sh
nix-termux doctor --json
```

The installer writes project files below:

```text
$HOME/.nix-termux
```

and exposes thin wrappers in:

```text
$PREFIX/bin
```

The wrapper set includes `nix`, `nix-shell`, `nix-env`, `nix-store`,
`nix-build`, `nix-channel`, `nix-collect-garbage`, `nix-copy-closure`,
`nix-hash`, `nix-instantiate`, and `nix-prefetch-url`.

Those wrappers are what Termux add-ons should call. For example,
`Termux:Widget` can run a script that executes:

```sh
nix-termux run nixpkgs#hello
```

Legacy scripts that use commands like `nix-shell '<nixpkgs>'` also go through
the wrappers. By default the runtime sets `NIX_PATH=nixpkgs=flake:nixpkgs`;
set `NIX_TERMUX_NIX_PATH` before calling a wrapper to use a local checkout or
another nixpkgs source.

For local development or mirrored artifacts, the installer also accepts
`NIX_TERMUX_CHANNEL_URL`, `NIX_TERMUX_ARCH`, `NIX_TERMUX_BOOTSTRAP_URL`, and
`NIX_TERMUX_BOOTSTRAP_SHA256` directly.
When running a standalone `install.sh` outside a source checkout or existing
installation, provide either
`NIX_TERMUX_CHANNEL_BASE_URL`, `NIX_TERMUX_CHANNEL_URL`, or
`NIX_TERMUX_RUNTIME_ARCHIVE_URL` so the installer can fetch the runtime files.

After installation, the saved channel can be reused to upgrade the runtime and
bootstrap:

```sh
nix-termux upgrade
```

or replaced explicitly:

```sh
nix-termux upgrade https://example.invalid/nix-termux/nix-termux-channel-aarch64.json
```

To refresh only the bootstrap, the saved bootstrap manifest can be reused with:

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
