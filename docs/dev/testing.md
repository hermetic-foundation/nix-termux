# Testing

## Full Host Suite

Run all flake checks before publishing:

```sh
nix flake check -L
```

The suite builds test dependencies through Nix. No global ShellCheck or
formatter installation is required.

## Focused Checks

| Changed area | Command |
| --- | --- |
| Installer or runtime | `nix develop -c sh tests/smoke/install.sh` |
| Documentation | `nix develop -c sh tests/smoke/docs-install.sh` |
| Shell formatting | `nix develop -c shfmt -d bin installer runtime tools tests` |
| Shell diagnostics | `nix develop -c shellcheck <changed-scripts>` |
| Release assembly | `nix build .#release-aarch64 -L` |

The complete flake check remains the acceptance command. Focused checks only
shorten the edit loop.

## Host Smoke Tests

`tests/smoke/install.sh` creates a temporary Termux-like prefix. It validates:

- Standalone, mirrored, and source-checkout installation
- Manifest validation and architecture matching
- Archive hashes and safe extraction paths
- Bootstrap store registration
- Configuration scaffold, activation, overrides, and preservation
- Wrapper backup, replacement, upgrade, and removal
- PRoot arguments and guest environment
- Failure behavior for missing or malformed inputs

Other scripts own artifact layout, schema, helper-tool, workflow, and
documentation checks.

## Release Artifacts

Build the physical-device bundle:

```sh
nix build .#release-aarch64 -L
tools/serve-release.sh --check result
```

The release check verifies checksums, manifest relationships, archive layout,
bootstrap registration, and the target executable architecture.

## Android Acceptance

Host PRoot substitutes are not equivalent to the Termux SELinux domain.
Runtime changes require the packaged device test:

```sh
nix-termux smoke-test --network
```

Use the [device validation guide](device-validation.md) to stage a local release
on an emulator or physical device.
