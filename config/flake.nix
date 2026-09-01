# SPDX-License-Identifier: AGPL-3.0-or-later

{
  description = "nix-termux user configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { ... }:
    let
      lock = builtins.fromJSON (builtins.readFile ./flake.lock);
      nixpkgsNode = lock.nodes.root.inputs.nixpkgs;
      lockedNixpkgs = builtins.removeAttrs lock.nodes.${nixpkgsNode}.locked [
        "lastModified"
        "revCount"
      ];

      registry = {
        version = 2;
        flakes = [
          {
            from = {
              type = "indirect";
              id = "nixpkgs";
            };
            to = lockedNixpkgs;
            exact = true;
          }
        ];
      };

      registryFile = builtins.toFile "nix-termux-registry.json" (
        builtins.toJSON registry
      );

      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        flake-registry = registryFile;
        substituters = [ "https://cache.nixos.org/" ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        ];
      };

      renderScalar = value:
        if builtins.isBool value then
          if value then "true" else "false"
        else if builtins.isInt value || builtins.isString value || builtins.isPath value then
          toString value
        else
          throw "nix-termux settings must contain strings, integers, booleans, paths, or lists of those values";

      renderValue = value:
        if builtins.isList value then
          builtins.concatStringsSep " " (map renderScalar value)
        else
          renderScalar value;

      nixConfig = builtins.concatStringsSep "\n"
        (
          map (name: "${name} = ${renderValue settings.${name}}") (
            builtins.attrNames settings
          )
        ) + "\n";
    in
    {
      nixTermux = {
        inherit lockedNixpkgs nixConfig registry registryFile settings;
      };
    };
}
