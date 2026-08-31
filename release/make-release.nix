# SPDX-License-Identifier: AGPL-3.0-or-later

{ runCommand
, coreutils
, targetSystem
, installer
, runtimeArchive
, channel
, bootstrap
}:

runCommand "nix-termux-release-${targetSystem}" {
  nativeBuildInputs = [ coreutils ];
  inherit
    installer
    runtimeArchive
    channel
    bootstrap
    ;
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
''
