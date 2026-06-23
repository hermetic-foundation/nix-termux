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
