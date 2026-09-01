# Contributing to nix-termux

This is the starting point for repository development. User-facing behavior
belongs in the [user documentation](docs/user/README.md); implementation and
release details belong in the [developer documentation](docs/dev/README.md).

## Prerequisites

- Nix with flakes enabled
- Jujutsu (`jj`) installed on the host
- `direnv`, if automatic shell activation is preferred
- Android platform tools for physical-device testing
- Android SDK emulator tools for emulator testing

The development shell intentionally does not provide `jj`. Repository history
must use the host installation.

## Get Started

Clone with Jujutsu:

```sh
jj git clone git@github.com:hermetic-foundation/nix-termux.git
cd nix-termux
```

Enter the development environment with either command:

```sh
direnv allow
```

```sh
nix develop
```

Run the complete host validation suite:

```sh
nix flake check -L
```

## Repository Map

| Path | Purpose |
| --- | --- |
| `installer/` | Installation, upgrade, and bootstrap activation |
| `runtime/` | PRoot environment and command dispatch |
| `bootstrap/` | Seed Nix closure and manifest schema |
| `channel/` | Release channel manifest |
| `release/` | Hostable release assembly |
| `tools/` | Release serving and Android validation |
| `tests/` | Host smoke tests and on-device acceptance tests |
| `docs/user/` | Installation and usage documentation |
| `docs/dev/` | Architecture, contracts, testing, and release docs |

## Development Guides

Read the documents relevant to the change before editing:

- [Architecture](docs/dev/architecture.md)
- [Testing](docs/dev/testing.md)
- [Bootstrap contract](docs/dev/bootstrap.md)
- [Channel contract](docs/dev/channel.md)
- [Doctor JSON contract](docs/dev/doctor.md)
- [Device validation](docs/dev/device-validation.md)
- [Release process](docs/dev/release.md)

## Change Workflow

1. Start a new Jujutsu change from the current `main` bookmark.
2. Keep implementation, tests, and documentation in one coherent change.
3. Run focused checks while iterating.
4. Run `nix flake check -L` before publishing.
5. Use a Conventional Commit description.
6. Rebase onto the current remote `main` before pushing.

Example:

```sh
jj git fetch --remote origin
jj new main@origin
jj describe -m "fix: describe the change"
nix flake check -L
jj bookmark move main --to @
jj git push --bookmark main --remote origin
```

## Documentation Standards

- Keep user procedures in `docs/user`.
- Keep implementation details in `docs/dev`.
- Use short paragraphs and descriptive headings.
- Use tables for compact reference material.
- Keep list items concise and nest supporting details under the correct item.
- Mark unvalidated behavior as unvalidated.
- Update commands and links in the same change as behavior.

## Android Acceptance

Host checks do not replace Android validation. Changes to the installer,
runtime, bootstrap, or wrapper behavior require the on-device smoke test.

Follow [device validation](docs/dev/device-validation.md) for emulator and
physical-device commands.
