# Configuration Contract

## Purpose

The user configuration is a locked flake. It replaces ad hoc generation of
files below `~/.config/nix` as the primary settings model.

The installed default is:

```text
$HOME/.config/nix-termux/
  flake.nix
  flake.lock
```

## Required Output

The activation helper evaluates:

```text
<flake-reference>#nixTermux.nixConfig
```

The output must be a raw string in `nix.conf` syntax. The template renders a
typed `settings` attribute set and creates a registry JSON file with
`builtins.toFile`.

The default registry maps the indirect `nixpkgs` identifier to the exact
reference recorded in `flake.lock`. Reading the lock avoids fetching the full
nixpkgs source during activation. Nix fetches it when a command resolves the
registry entry.

## Activation Sequence

`runtime/activate-config.sh` runs inside PRoot before every requested command:

1. Require `flake.nix` and `flake.lock` for a local reference.
2. Invoke the bootstrap Nix binary directly.
3. Disable input-provided flake settings with `accept-flake-config = false`.
4. Evaluate `nixTermux.nixConfig` without writing a lock file.
5. Prepend the rendered text to inherited `NIX_CONFIG`.
6. Execute the requested command.

Inherited `NIX_CONFIG` appears last and has per-command override precedence.
The base bootstrap file at `/etc/nix/nix.conf` still supplies runtime settings
required before activation.

The generated registry is Nix's global registry. An explicit user registry or
`--override-flake` remains higher precedence by Nix contract. The runtime does
not mutate `~/.config/nix/registry.json`.

## Escape Hatches

| Variable | Behavior |
| --- | --- |
| `NIX_TERMUX_CONFIG_FLAKE` | Select a guest-visible flake reference |
| `NIX_TERMUX_CONFIG_FLAKE=none` | Skip flake activation |
| `NIX_TERMUX_REAL_NIX` | Select the Nix binary used by the helper |
| `NIX_CONFIG` | Append per-command Nix settings |

The installer sets `NIX_TERMUX_CONFIG_FLAKE=none` while loading bootstrap store
registrations. This keeps recovery and upgrades independent of user config
validity.

## Install and Upgrade Rules

- A fresh install copies both template files.
- An existing configuration is never overwritten.
- A partial configuration is preserved and reported as a warning.
- The uninstaller removes managed state but preserves user configuration.
- `doctor` requires a readable flake, lock, and activation helper.

Shipped templates live below `$HOME/.nix-termux/share/config`. They are updated
with runtime artifacts without replacing the user's copy.

## Compatibility

The contract is additive to the existing CLI. Legacy `NIX_PATH` remains mapped
to `flake:nixpkgs`, which resolves through the activated registry.

Do not move settings solely into the standard flake `nixConfig` attribute. Nix
applies that attribute while consuming a flake and can require interactive
acceptance; it is not the nix-termux activation contract.

## Validation Ownership

| Check | Coverage |
| --- | --- |
| `configuration-flake` | Rendered text, registry JSON, and lock consistency |
| `install-smoke` | Scaffolding, activation, overrides, errors, and preservation |
| `runtime-archive` | Template and helper artifact layout |
| Device smoke | PRoot activation and registry resolution on Android |
