# Current Limitations

## Supported Model

`nix-termux` provides single-user Nix for Linux packages on Android. It is not
a NixOS distribution or an Android package manager.

The current release target is `aarch64-linux`.

## Unavailable Features

- Multi-user Nix
- The Nix daemon
- Sandboxed builds
- NixOS activation and `nixos-rebuild`
- systemd system services
- Real mounts and privileged namespaces
- Docker, Podman, KVM, and kernel modules
- Direct execution of `/nix/store` programs outside PRoot

## PRoot Boundaries

- `/nix` exists only inside the PRoot environment.
- Nix profile and `result` symlinks appear broken in outer Termux.
- Absolute Termux paths are not automatically rewritten to guest paths.
- Commands start in `/home/termux`, not the outer shell's current subdirectory.
- Programs that require restricted Android syscalls can fail.
- Source builds are slower than native execution and may expose compatibility
  issues not seen with cached packages.

## Validation Coverage

The physical-device acceptance test currently verifies:

- Bootstrap activation and local store access
- Every installed Nix wrapper starting successfully
- DNS and certificate configuration
- Locked configuration activation and `nixpkgs` registry resolution
- `nix run nixpkgs#hello` through the public binary cache

The following workflows still need dedicated hardware coverage:

- Local source builds
- `nix develop`
- Profile install, update, and removal
- Garbage collection with a populated store
- Legacy channels
- Remote builders and store copies
- Termux:Widget, Termux:Tasker, and Termux:API integration
