# User Guide

`nix-termux` runs single-user Nix inside stock Termux through a small PRoot
environment.

## Start Here

1. [Install nix-termux](install.md).
2. [Run Nix commands](usage.md).
3. [Configure registries and binary caches](configuration.md).
4. Review the [current limitations](limitations.md).
5. Use the [troubleshooting guide](troubleshooting.md) when a check fails.

## Quick Reference

| Task | Command |
| --- | --- |
| Check the installation | `nix-termux doctor` |
| Run a flake app | `nix run nixpkgs#hello` |
| Enter the Nix environment | `nix-termux enter` |
| Edit Nix settings | `$EDITOR ~/.config/nix-termux/flake.nix` |
| Run an installed program | `nix-termux exec <command>` |
| Update nix-termux | `nix-termux upgrade` |
| Run acceptance checks | `nix-termux smoke-test --network` |
| Remove nix-termux | `nix-termux uninstall` |

Developer material starts in [CONTRIBUTING.md](../../CONTRIBUTING.md).
