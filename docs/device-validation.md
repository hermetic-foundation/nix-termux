# Device Validation

Host CI proves the installer contract and artifact layout. Android support is
accepted only after running the device smoke test inside stock Termux.

Install a release build on the device:

```sh
pkg install proot curl tar xz coreutils
export NIX_TERMUX_CHANNEL_BASE_URL=https://github.com/midischwarz12/nix-termux/releases/download/v0.1.0
curl -L https://github.com/midischwarz12/nix-termux/releases/download/v0.1.0/install.sh | sh
```

Then run:

```sh
nix-termux doctor --json
sh "$HOME/.nix-termux/share/tests/device-smoke.sh"
```

The smoke test checks Termux detection, wrapper installation, `proot`, the Nix
store/profile layout, certificate bundle wiring, bootstrap activation, and basic
`nix`/`nix-store` execution through the wrappers.

Networked Nix evaluation is intentionally opt-in because it can be slow and
depends on the device connection:

```sh
NIX_TERMUX_DEVICE_SMOKE_NETWORK=1 sh "$HOME/.nix-termux/share/tests/device-smoke.sh"
```

For unpublished or mirrored artifacts, point the installer at a local channel:

```sh
export NIX_TERMUX_CHANNEL_BASE_URL=https://example.invalid/nix-termux
curl -L "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh" | sh
sh "$HOME/.nix-termux/share/tests/device-smoke.sh"
```

The first supported target is `aarch64` Termux. Other architectures can use the
same smoke test once matching channel and bootstrap artifacts exist.
