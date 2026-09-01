# Device Validation

## Acceptance Rule

Host CI validates contracts and artifact layout. Android support is accepted
only after the packaged smoke test passes inside an interactive stock Termux
session.

Do not use `adb shell run-as com.termux` as the runtime test. It runs under a
different SELinux domain and does not reproduce Termux's `LD_PRELOAD` behavior.

## Build a Device Release

Build the ARM64 bundle on the development host:

```sh
nix build .#release-aarch64 -L
tools/serve-release.sh --check result
```

`release-aarch64` can be cross-built on x86_64 Linux. The native `release`
output is for a device or emulator matching the host architecture.

## Serve the Bundle

Choose an address reachable from the Android device:

```sh
tools/serve-release.sh result 192.0.2.10 8000
```

The helper performs release validation before starting the server. It prints
the exact Termux installation and smoke-test commands.

Validation covers:

- `install.sh.sha256`
- `nix-termux-runtime.tar.gz.sha256`
- Aggregate `SHA256SUMS`
- Channel and bootstrap manifest relationships
- Bootstrap registration sidecars

## Stage with ADB

USB debugging can stage the Termux-side script:

```sh
tools/adb-validate.sh --network http://192.0.2.10:8000
```

The helper writes `/sdcard/Download/nix-termux-validate.sh`, opens Termux, and
prints the command the tester must run interactively.

ADB cannot directly execute that final command in an equivalent app context.

## Run Acceptance Checks

Inside Termux, run:

```sh
nix-termux doctor --json
nix-termux smoke-test --network
```

The networked test verifies `nix run nixpkgs#hello`. Use `--no-network` for an
offline structural check.

The device test covers:

- Termux and PRoot discovery
- Store, profile, and bootstrap activation
- Every installed Nix wrapper
- Guest identity, DNS, certificates, and writable state
- Runtime environment variables
- Absence of the Android `/proc/stat` GC warning
- Public cache download and execution when network testing is enabled

## Android Emulator

### Prerequisites

- Android SDK `emulator`, `sdkmanager`, and `avdmanager`
- Android platform tools on `PATH`
- An existing Android Virtual Device
- A stock Termux APK matching the emulator architecture
- A matching local release bundle

### Start and Validate

For an x86_64 AVD and native release:

```sh
nix build .#release -L
tools/emulator-validate.sh \
  --avd nix-termux-api-35 \
  --termux-apk ~/Downloads/termux.apk \
  --network
```

Use `.#release-aarch64` for an ARM64 AVD.

The helper serves files on host loopback. Android reaches them through
`10.0.2.2`.

### Reuse a Running Emulator

```sh
tools/emulator-validate.sh \
  --no-start \
  --serial emulator-5554 \
  --network
```

### Inspect Commands Only

```sh
tools/emulator-validate.sh \
  --dry-run \
  --avd nix-termux-api-35 \
  --network
```

## Validated Platform

The current ARM64 flow has passed in Termux `0.118.3` from GitHub on an Android
16 physical device. The test included a networked `nixpkgs#hello` execution.
