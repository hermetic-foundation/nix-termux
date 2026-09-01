# Use nix-termux

## Command Reference

| Command | Purpose |
| --- | --- |
| `nix-termux doctor` | Check runtime readiness |
| `nix-termux env` | Print runtime paths and environment |
| `nix-termux enter` | Start an interactive Nix shell |
| `nix-termux exec <command>` | Run any command inside PRoot |
| `nix-termux run <installable>` | Run `nix run <installable>` |
| `nix-termux smoke-test` | Run device acceptance checks |
| `nix-termux upgrade` | Update from the saved channel |
| `nix-termux uninstall` | Remove the installation |

The installer also creates wrappers for the modern `nix` command and common
legacy commands such as `nix-shell`, `nix-build`, and `nix-store`.

Each wrapper activates the locked settings from
`~/.config/nix-termux/flake.nix`. See the
[configuration guide](configuration.md) for registries and binary caches.

The examples below use standard single-user Nix interfaces. The current Android
acceptance test covers `nix run`; other workflows are listed separately in the
[validation gaps](limitations.md#validation-coverage).

## Run Packages

```sh
nix run nixpkgs#hello
nix shell nixpkgs#git -c git --version
nix eval nixpkgs#hello.meta.description
```

Arguments pass through the wrapper unchanged:

```sh
nix run nixpkgs#ripgrep -- --version
```

## Work on a Local Project

Enter PRoot before changing to the project directory:

```sh
nix-termux enter
cd ~/src/my-project
nix develop
```

The current wrapper starts commands in `/home/termux`. It does not preserve a
subdirectory selected in the outer Termux shell.

## Install Programs into a Profile

```sh
nix profile install nixpkgs#jq
nix-termux exec jq --version
```

Profile programs are automatically on `PATH` inside `nix-termux enter`. They
are not directly executable from the outer Termux environment.

## Use Legacy Nix Commands

The default `NIX_PATH` maps `nixpkgs` to the flake registry:

```sh
nix-shell '<nixpkgs>' -p git jq
```

Use another source by setting `NIX_TERMUX_NIX_PATH` before the wrapper:

```sh
NIX_TERMUX_NIX_PATH=nixpkgs=/home/termux/src/nixpkgs nix-shell '<nixpkgs>'
```

Paths passed into PRoot must use its path layout.

## Use Termux Add-ons

Termux:Widget can execute a normal Termux script:

```sh
#!/data/data/com.termux/files/usr/bin/sh
nix-termux run nixpkgs#hello
```

The add-on invokes the wrapper in stock Termux. It does not need direct access
to the private Nix store.

Calling Termux:API commands from inside PRoot is not yet a supported workflow.

## Access Android Storage

The runtime binds `/sdcard` and `/storage` when those paths exist. Grant Termux
storage access first when shared storage is required:

```sh
termux-setup-storage
```

Override the optional bind list before entering PRoot:

```sh
NIX_TERMUX_ANDROID_BIND_DIRS="/sdcard /storage" nix-termux enter
```
