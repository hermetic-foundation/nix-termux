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
              install -Dm755 tools/adb-validate.sh "$out/share/nix-termux/tools/adb-validate.sh"
              install -Dm755 tools/serve-release.sh "$out/share/nix-termux/tools/serve-release.sh"
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

          release = pkgs.runCommand "nix-termux-release-${system}" {
            nativeBuildInputs = [ pkgs.coreutils ];
            installer = self.packages.${system}.installer;
            runtimeArchive = self.packages.${system}.runtime-archive;
            channel = self.packages.${system}.channel;
            bootstrap = self.packages.${system}.bootstrap;
          } ''
            mkdir -p "$out"
            cp --no-preserve=mode "$installer"/* "$out"/
            cp --no-preserve=mode "$runtimeArchive"/* "$out"/
            cp --no-preserve=mode "$channel"/* "$out"/
            cp --no-preserve=mode "$bootstrap"/* "$out"/
            chmod 755 "$out"/install.sh
            (cd "$out" && sha256sum \
              install.sh \
              install.sh.sha256 \
              nix-termux-runtime.tar.gz \
              nix-termux-runtime.tar.gz.sha256 \
              nix-termux-channel-*.json \
              nix-termux-bootstrap-*.tar.gz \
              nix-termux-bootstrap-*.json \
              nix-termux-bootstrap-*.registration \
              > SHA256SUMS)
          '';
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
            "tools/adb-validate.sh"
            "tools/serve-release.sh"
            "tests/smoke/adb-validate.sh"
            "tests/smoke/bootstrap-artifact.sh"
            "tests/smoke/channel-artifact.sh"
            "tests/smoke/device-smoke-options.sh"
            "tests/smoke/docs-install.sh"
            "tests/smoke/github-actions.sh"
            "tests/smoke/install.sh"
            "tests/smoke/runtime-archive.sh"
            "tests/smoke/serve-release.sh"
            "tests/smoke/version-consistency.sh"
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
            nativeBuildInputs = [
              pkgs.actionlint
              pkgs.gnugrep
            ];
            src = self;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            actionlint .github/workflows/ci.yml
            sh tests/smoke/github-actions.sh
            touch "$out"
          '';

          version-consistency = pkgs.runCommand "nix-termux-version-consistency" {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnused
            ];
            src = self;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            sh tests/smoke/version-consistency.sh
            touch "$out"
          '';

          device-smoke-options = pkgs.runCommand "nix-termux-device-smoke-options" {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
            ];
            src = self;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            sh tests/smoke/device-smoke-options.sh
            touch "$out"
          '';

          docs-install = pkgs.runCommand "nix-termux-docs-install-smoke" {
            nativeBuildInputs = [
              pkgs.gnugrep
              pkgs.ripgrep
            ];
            src = self;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            sh tests/smoke/docs-install.sh
            touch "$out"
          '';

          manifest-schemas = pkgs.runCommand "nix-termux-manifest-schemas" {
            nativeBuildInputs = [
              (pkgs.python3.withPackages (pythonPackages: [
                pythonPackages.jsonschema
              ]))
            ];
            src = self;
            bootstrapArtifact = self.packages.${system}.bootstrap;
            channelArtifact = self.packages.${system}.channel;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            python tests/smoke/manifest-schemas.py \
              bootstrap/manifest.schema.json \
              channel/schema.json \
              "$bootstrapArtifact" \
              "$channelArtifact"
            touch "$out"
          '';

          adb-validate = pkgs.runCommand "nix-termux-adb-validate-smoke" {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
            ];
            src = self;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            sh tests/smoke/adb-validate.sh
            touch "$out"
          '';

          serve-release = pkgs.runCommand "nix-termux-serve-release-smoke" {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.python3
            ];
            src = self;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            sh tests/smoke/serve-release.sh
            touch "$out"
          '';

          bootstrap-artifact = pkgs.runCommand "nix-termux-bootstrap-artifact-smoke" {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.gnugrep
              pkgs.gnutar
              pkgs.gzip
              pkgs.jq
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
            runtimeArtifact = self.packages.${system}.runtime-archive;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            sh tests/smoke/channel-artifact.sh "$artifact" "$runtimeArtifact"
            touch "$out"
          '';

          runtime-archive = pkgs.runCommand "nix-termux-runtime-archive-smoke" {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnutar
              pkgs.gzip
            ];
            src = self;
            artifact = self.packages.${system}.runtime-archive;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            sh tests/smoke/runtime-archive.sh "$artifact"
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

          package-artifact = pkgs.runCommand "nix-termux-package-artifact-smoke" {
            artifact = self.packages.${system}.default;
          } ''
            test -x "$artifact"/bin/nix-termux
            test -x "$artifact"/share/nix-termux/installer/install.sh
            test -x "$artifact"/share/nix-termux/installer/uninstall.sh
            test -x "$artifact"/share/nix-termux/tools/adb-validate.sh
            test -x "$artifact"/share/nix-termux/tools/serve-release.sh
            test -x "$artifact"/share/nix-termux/tests/device-smoke.sh
            grep -q 'SPDX-License-Identifier: AGPL-3.0-or-later' "$artifact"/bin/nix-termux
            grep -q 'SPDX-License-Identifier: AGPL-3.0-or-later' "$artifact"/share/nix-termux/installer/install.sh
            grep -q 'SPDX-License-Identifier: AGPL-3.0-or-later' "$artifact"/share/nix-termux/installer/uninstall.sh
            grep -q 'SPDX-License-Identifier: AGPL-3.0-or-later' "$artifact"/share/nix-termux/tools/adb-validate.sh
            grep -q 'SPDX-License-Identifier: AGPL-3.0-or-later' "$artifact"/share/nix-termux/tools/serve-release.sh
            grep -q 'SPDX-License-Identifier: AGPL-3.0-or-later' "$artifact"/share/nix-termux/tests/device-smoke.sh
            test -r "$artifact"/share/doc/nix-termux/device-validation.md
            test -r "$artifact"/share/licenses/nix-termux/LICENSE
            grep -q 'GNU AFFERO GENERAL PUBLIC LICENSE' "$artifact"/share/licenses/nix-termux/LICENSE
            test -r "$artifact"/share/nix-termux/bootstrap/manifest.schema.json
            test -r "$artifact"/share/nix-termux/channel/schema.json
            test "$(PATH="$artifact/bin:$PATH" nix-termux version)" = "0.1.0"
            touch "$out"
          '';

          release-artifact = pkgs.runCommand "nix-termux-release-artifact-smoke" {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.gnugrep
              pkgs.gnused
            ];
            src = self;
            artifact = self.packages.${system}.release;
          } ''
            test -x "$artifact"/install.sh
            test -r "$artifact"/nix-termux-runtime.tar.gz
            test -r "$artifact"/nix-termux-runtime.tar.gz.sha256
            test -r "$artifact"/SHA256SUMS
            test "$(find "$artifact" -name 'nix-termux-channel-*.json' | wc -l)" -eq 1
            test "$(find "$artifact" -name 'nix-termux-bootstrap-*.json' | wc -l)" -eq 1
            test "$(find "$artifact" -name 'nix-termux-bootstrap-*.tar.gz' | wc -l)" -eq 1
            test "$(find "$artifact" -name 'nix-termux-bootstrap-*.registration' | wc -l)" -eq 1
            grep -q 'nix-termux-runtime.tar.gz' "$artifact"/SHA256SUMS
            grep -q 'install.sh' "$artifact"/SHA256SUMS
            (cd "$artifact" && sha256sum -c install.sh.sha256)
            (cd "$artifact" && sha256sum -c SHA256SUMS)
            sh "$src"/tools/serve-release.sh --check "$artifact"
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
              python3
              android-tools
            ];
          };
        });

      formatter = forAllSystems (system:
        nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
