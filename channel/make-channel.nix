# SPDX-License-Identifier: AGPL-3.0-or-later

{ lib
, stdenvNoCC
, coreutils
, jq
, runtimeArchive
, bootstrap
, system
, termuxArch ? null
, runtimeUrl ? "nix-termux-runtime.tar.gz"
, bootstrapManifestUrl ? null
}:

let
  archMap = {
    aarch64-linux = "aarch64";
    armv7l-linux = "arm";
    i686-linux = "i686";
    x86_64-linux = "x86_64";
  };

  resolvedTermuxArch =
    if termuxArch != null then termuxArch
    else archMap.${system} or (throw "Unsupported channel system: ${system}");

  resolvedBootstrapManifestUrl =
    if bootstrapManifestUrl != null then bootstrapManifestUrl
    else "nix-termux-bootstrap-${resolvedTermuxArch}.json";
in
stdenvNoCC.mkDerivation {
  pname = "nix-termux-channel";
  version = "0.1.1";

  nativeBuildInputs = [
    coreutils
    jq
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    runtime_sha=$(sha256sum ${runtimeArchive}/nix-termux-runtime.tar.gz | awk '{print $1}')

    mkdir -p "$out"
    jq -n \
      --arg runtimeUrl ${lib.escapeShellArg runtimeUrl} \
      --arg runtimeSha "$runtime_sha" \
      --arg bootstrapManifestUrl ${lib.escapeShellArg resolvedBootstrapManifestUrl} \
      --arg termuxArch ${lib.escapeShellArg resolvedTermuxArch} \
      --arg nixSystem ${lib.escapeShellArg system} \
      '{
        schemaVersion: 1,
        platform: {
          termuxArch: $termuxArch,
          nixSystem: $nixSystem
        },
        runtime: {
          url: $runtimeUrl,
          sha256: $runtimeSha
        },
        bootstrapManifest: {
          url: $bootstrapManifestUrl
        }
      }' > "$out/nix-termux-channel-${resolvedTermuxArch}.json"

    cp ${bootstrap}/nix-termux-bootstrap-${resolvedTermuxArch}.json "$out/"

    runHook postInstall
  '';
}
