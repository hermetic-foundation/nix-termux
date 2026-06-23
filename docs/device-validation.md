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
nix-termux smoke-test
```

The smoke test checks Termux detection, wrapper installation, `proot`, the Nix
store/profile layout, certificate bundle wiring, bootstrap activation, and
basic execution through every installed Nix wrapper.

Networked Nix evaluation is intentionally opt-in because it can be slow and
depends on the device connection:

```sh
nix-termux smoke-test --network
```

Use `--no-network` to force an offline-only run when
`NIX_TERMUX_DEVICE_SMOKE_NETWORK=1` is set in the environment.

For unpublished or mirrored artifacts, point the installer at a local channel:

```sh
export NIX_TERMUX_CHANNEL_BASE_URL=https://example.invalid/nix-termux
curl -L "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh" | sh
nix-termux smoke-test
```

For a local release bundle, build and serve it from the host machine:

```sh
nix build .#release
tools/serve-release.sh result 192.0.2.10 8000
```

Use a host address that the Android device can reach over the local network.
The helper validates the release directory, prints the Termux install commands,
checks `SHA256SUMS`, and serves the files until interrupted.

With USB debugging enabled, you can also stage the Termux-side validation
script over `adb`:

```sh
tools/adb-validate.sh --network http://192.0.2.10:8000
```

The adb helper pushes a script to
`/sdcard/Download/nix-termux-validate.sh`, tries to bring Termux to the
foreground, and prints the command to run inside Termux. The pushed script
verifies `install.sh.sha256` before running the installer.

The command runs the installed script at
`$HOME/.nix-termux/share/tests/device-smoke.sh`. The first supported target is
`aarch64` Termux. Other architectures can use the same smoke test once matching
channel and bootstrap artifacts exist.
