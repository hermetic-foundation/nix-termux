# Configure nix-termux

## Default Configuration

Installation creates a locked flake at:

```text
~/.config/nix-termux/
  flake.nix
  flake.lock
```

The default flake controls:

- The `nixpkgs` registry entry
- Binary cache URLs
- Binary cache public keys
- Required experimental features

Upgrades and uninstallation preserve this directory.

## Edit Nix Settings

Open `~/.config/nix-termux/flake.nix` and edit the `settings` attribute set.
Values may be strings, integers, booleans, paths, or lists of those types.
They render to Nix configuration syntax.

For example, add a binary cache and its signing key:

```nix
settings = {
  experimental-features = [ "nix-command" "flakes" ];
  flake-registry = registryFile;
  substituters = [
    "https://cache.nixos.org/"
    "https://cache.example.invalid/"
  ];
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cache.example.invalid-1:replace-with-the-real-key"
  ];
};
```

Only add caches and keys controlled by a trusted operator. A trusted cache can
provide binaries that Nix will execute.

## Update the Registry Pin

The `nixpkgs` registry follows the flake's locked `nixpkgs` input. Activation
reads the locked reference without fetching the nixpkgs source.

Update the pin from inside the environment:

```sh
nix-termux enter
cd ~/.config/nix-termux
nix flake update
exit
```

Review `flake.lock` after an update. Keeping the lock file makes registry
resolution reproducible and prevents the runtime from following a moving
branch on each invocation.

## Apply Changes

Start a new wrapper command or PRoot session:

```sh
nix --version
nix-termux enter
```

The runtime evaluates `nixTermux.nixConfig` before executing the requested
command. The result is passed through `NIX_CONFIG` for that process only.

No file is generated in `~/.config/nix`. The locked flake remains the user
configuration source of truth.

Nix gives an existing user registry at `~/.config/nix/registry.json` and
command-line `--override-flake` arguments higher precedence than the configured
global registry. nix-termux does not create or remove that external file.

## Validate Changes

Evaluate the output without activating it first:

```sh
NIX_TERMUX_CONFIG_FLAKE=none \
  nix-termux exec nix eval --raw \
  path:/home/termux/.config/nix-termux#nixTermux.nixConfig
```

Check that the registry resolves its locked source:

```sh
nix-termux exec nix flake metadata --json nixpkgs
```

## Override Activation

Use another guest-visible flake for one command:

```sh
NIX_TERMUX_CONFIG_FLAKE=path:/home/termux/configs/nix-termux nix --version
```

Local configuration flakes must contain both `flake.nix` and `flake.lock`.

Disable activation for recovery or diagnosis:

```sh
NIX_TERMUX_CONFIG_FLAKE=none nix --version
```

An explicitly supplied `NIX_CONFIG` is appended after the flake output. It can
override a setting for one command:

```sh
NIX_CONFIG='max-jobs = 1' nix build nixpkgs#hello
```

## Flake Output Contract

A replacement configuration flake must expose one raw string:

```nix
{
  outputs = { self }: {
    nixTermux.nixConfig = ''
      experimental-features = nix-command flakes
      substituters = https://cache.nixos.org/
    '';
  };
}
```

The installed template includes typed rendering and a locked registry. Keep
those helpers unless a different rendering model is required.
