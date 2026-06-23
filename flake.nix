{
  description = "Nix in stock Termux through a small proot-backed runtime";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "nix-termux";
            version = "0.1.0";
            src = self;

            installPhase = ''
              runHook preInstall
              install -Dm755 bin/nix-termux "$out/bin/nix-termux"
              install -Dm755 installer/install.sh "$out/share/nix-termux/installer/install.sh"
              install -Dm755 installer/uninstall.sh "$out/share/nix-termux/installer/uninstall.sh"
              install -Dm644 LICENSE "$out/share/licenses/nix-termux/LICENSE"
              install -Dm644 README.md "$out/share/doc/nix-termux/README.md"
              install -Dm644 docs/architecture.md "$out/share/doc/nix-termux/architecture.md"
              install -Dm644 docs/bootstrap.md "$out/share/doc/nix-termux/bootstrap.md"
              install -Dm644 docs/channel.md "$out/share/doc/nix-termux/channel.md"
              install -Dm644 docs/device-validation.md "$out/share/doc/nix-termux/device-validation.md"
              install -Dm644 docs/doctor.md "$out/share/doc/nix-termux/doctor.md"
              install -Dm644 docs/release.md "$out/share/doc/nix-termux/release.md"
              install -Dm755 tests/termux/device-smoke.sh "$out/share/nix-termux/tests/device-smoke.sh"
              install -Dm644 bootstrap/manifest.schema.json "$out/share/nix-termux/bootstrap/manifest.schema.json"
              install -Dm644 bootstrap/example-manifest.json "$out/share/nix-termux/bootstrap/example-manifest.json"
              install -Dm644 channel/schema.json "$out/share/nix-termux/channel/schema.json"
              cp -R runtime "$out/share/nix-termux/runtime"
              runHook postInstall
            '';

            meta = {
              description = "Installer and runtime wrappers for Nix in stock Termux";
              homepage = "https://github.com/midischwarz12/nix-termux";
              license = pkgs.lib.licenses.agpl3Plus;
              mainProgram = "nix-termux";
              platforms = supportedSystems;
            };
          };

          bootstrap = pkgs.callPackage ./bootstrap/make-bootstrap.nix {
            inherit system;
          };

          installer = pkgs.callPackage ./installer/make-installer.nix { };

          runtime-archive = pkgs.callPackage ./runtime/make-runtime-archive.nix { };

          channel = pkgs.callPackage ./channel/make-channel.nix {
            inherit system;
            runtimeArchive = self.packages.${system}.runtime-archive;
            bootstrap = self.packages.${system}.bootstrap;
          };
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/nix-termux";
          meta.description = "Run the nix-termux CLI";
        };
      });

      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          scripts = [
            "bin/nix-termux"
            "installer/install.sh"
            "installer/uninstall.sh"
            "runtime/nix-termux.sh"
            "tests/smoke/bootstrap-artifact.sh"
            "tests/smoke/channel-artifact.sh"
            "tests/smoke/install.sh"
            "tests/termux/device-smoke.sh"
          ];
        in
        {
          shell-format = pkgs.runCommand "nix-termux-shell-format" {
            nativeBuildInputs = [ pkgs.shfmt ];
            src = self;
          } ''
            cp -R "$src" source
            cd source
            shfmt -d ${builtins.concatStringsSep " " scripts}
            touch "$out"
          '';

          shellcheck = pkgs.runCommand "nix-termux-shellcheck" {
            nativeBuildInputs = [ pkgs.shellcheck ];
            src = self;
          } ''
            cp -R "$src" source
            cd source
            shellcheck ${builtins.concatStringsSep " " scripts}
            touch "$out"
          '';

          install-smoke = pkgs.runCommand "nix-termux-install-smoke" {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.curl
              pkgs.gnutar
              pkgs.jq
            ];
            src = self;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            sh tests/smoke/install.sh
            touch "$out"
          '';

          github-actions = pkgs.runCommand "nix-termux-github-actions" {
            nativeBuildInputs = [ pkgs.actionlint ];
            src = self;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            actionlint .github/workflows/ci.yml
            touch "$out"
          '';

          bootstrap-artifact = pkgs.runCommand "nix-termux-bootstrap-artifact-smoke" {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.gnugrep
              pkgs.gnutar
              pkgs.gzip
            ];
            src = self;
            artifact = self.packages.${system}.bootstrap;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            sh tests/smoke/bootstrap-artifact.sh "$artifact"
            touch "$out"
          '';

          channel-artifact = pkgs.runCommand "nix-termux-channel-artifact-smoke" {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.jq
            ];
            src = self;
            artifact = self.packages.${system}.channel;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            sh tests/smoke/channel-artifact.sh "$artifact"
            touch "$out"
          '';

          runtime-archive = pkgs.runCommand "nix-termux-runtime-archive-smoke" {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnutar
              pkgs.gzip
            ];
            artifact = self.packages.${system}.runtime-archive;
          } ''
            tar -tzf "$artifact"/nix-termux-runtime.tar.gz > listing
            grep -qx './bin/nix-termux' listing
            grep -qx './installer/install.sh' listing
            grep -qx './installer/uninstall.sh' listing
            grep -qx './runtime/nix-termux.sh' listing
            grep -qx './tests/termux/device-smoke.sh' listing
            grep -qx './LICENSE' listing
            (cd "$artifact" && sha256sum -c nix-termux-runtime.tar.gz.sha256)
            touch "$out"
          '';

          installer-artifact = pkgs.runCommand "nix-termux-installer-artifact-smoke" {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
            ];
            artifact = self.packages.${system}.installer;
          } ''
            test -x "$artifact"/install.sh
            grep -q 'SPDX-License-Identifier: AGPL-3.0-or-later' "$artifact"/install.sh
            (cd "$artifact" && sha256sum -c install.sh.sha256)
            touch "$out"
          '';
        });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              bash
              coreutils
              git
              actionlint
              jq
              shellcheck
              shfmt
              jj
            ];
          };
        });

      formatter = forAllSystems (system:
        nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
