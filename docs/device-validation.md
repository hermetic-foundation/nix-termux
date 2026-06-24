# Device Validation

Host CI proves the installer contract and artifact layout. Android support is
accepted only after running the device smoke test inside stock Termux.

Install a release build on the device:

```sh
pkg install proot curl tar xz coreutils
export NIX_TERMUX_CHANNEL_BASE_URL=https://github.com/midischwarz12/nix-termux/releases/download/v0.1.0
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh" -o "$tmp_dir/install.sh"
curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh.sha256" -o "$tmp_dir/install.sh.sha256"
(cd "$tmp_dir" && sha256sum -c install.sh.sha256)
sh "$tmp_dir/install.sh"
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
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh" -o "$tmp_dir/install.sh"
curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh.sha256" -o "$tmp_dir/install.sh.sha256"
(cd "$tmp_dir" && sha256sum -c install.sh.sha256)
sh "$tmp_dir/install.sh"
nix-termux smoke-test
```

For a local release bundle, build and serve it from the host machine:

```sh
nix build .#release
tools/serve-release.sh --check result
tools/serve-release.sh result 192.0.2.10 8000
```

Use a host address that the Android device can reach over the local network.
The helper validates the release directory, prints the Termux install commands,
checks `install.sh.sha256`, `nix-termux-runtime.tar.gz.sha256`, bootstrap
registration sidecars, and `SHA256SUMS`, then serves the files until
interrupted.

With USB debugging enabled, you can also stage the Termux-side validation
script over `adb`:

```sh
tools/adb-validate.sh --network http://192.0.2.10:8000
```

The adb helper pushes a script to
`/sdcard/Download/nix-termux-validate.sh`, tries to bring Termux to the
foreground, and prints the command to run inside Termux. The pushed script
verifies `install.sh.sha256` before running the installer.

## Android Emulator

Emulator validation is useful before testing on a physical device. It still
uses stock Termux and the same on-device smoke test; the emulator helper only
starts the device, serves the release, installs an optional Termux APK, and
stages the validation script.

Prerequisites:

- Android SDK `emulator` and platform tools on `PATH`.
- An existing AVD, for example one created by Android Studio.
- A Termux APK from F-Droid or the Termux GitHub releases.
- A local release build from `nix build .#release`.

Run:

```sh
nix build .#release
tools/emulator-validate.sh \
  --avd nix-termux-api-35 \
  --termux-apk ~/Downloads/termux.apk \
  --network
```

The helper serves the release on `127.0.0.1:8000` and points the emulator at
`http://10.0.2.2:8000`, which is the Android emulator address for the host
loopback interface. It prints the command to run inside Termux, then keeps the
release server alive until interrupted.

For an already-running emulator or device:

```sh
tools/emulator-validate.sh --no-start --serial emulator-5554 --network
```

To inspect the commands without starting anything:

```sh
tools/emulator-validate.sh --dry-run --avd nix-termux-api-35 --network
```

The command runs the installed script at
`$HOME/.nix-termux/share/tests/device-smoke.sh`. The first supported target is
`aarch64` Termux. Other architectures can use the same smoke test once matching
channel and bootstrap artifacts exist.
