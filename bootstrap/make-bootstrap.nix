{ lib
, stdenvNoCC
, closureInfo
, coreutils
, gnugrep
, gnused
, gnutar
, gzip
, jq
, nix
, bashInteractive
, cacert
, system
, termuxArch ? null
, archiveUrl ? null
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
    else archMap.${system} or (throw "Unsupported bootstrap system: ${system}");

  profilePackages = [
    nix
    bashInteractive
    coreutils
    cacert
  ];

  closure = closureInfo {
    rootPaths = profilePackages;
  };
in
stdenvNoCC.mkDerivation {
  pname = "nix-termux-bootstrap";
  version = "0.1.0";

  nativeBuildInputs = [
    coreutils
    gnugrep
    gnused
    gnutar
    gzip
    jq
  ];

  dontUnpack = true;

  buildPhase = ''
    runHook preBuild

    mkdir -p \
      bootstrap/nix/store \
      bootstrap/nix/var/log/nix/drvs \
      bootstrap/nix/var/nix/db \
      bootstrap/nix/var/nix/gcroots/auto \
      bootstrap/nix/var/nix/profiles/default/bin \
      bootstrap/nix/var/nix/profiles/default/etc/ssl/certs \
      bootstrap/nix/var/nix/profiles/per-user/termux \
      bootstrap/nix/var/nix/temproots \
      bootstrap/nix-termux \
      bootstrap/root/etc/nix \
      bootstrap/root/home \
      bootstrap/root/tmp \
      bootstrap/root/usr/bin \
      bootstrap/root/bin

    while IFS= read -r path; do
      cp -a "$path" bootstrap/nix/store/
    done < ${closure}/store-paths

    ln -s ${nix}/bin/nix bootstrap/nix/var/nix/profiles/default/bin/nix
    ln -s ${nix}/bin/nix-env bootstrap/nix/var/nix/profiles/default/bin/nix-env
    ln -s ${nix}/bin/nix-store bootstrap/nix/var/nix/profiles/default/bin/nix-store
    ln -s ${nix}/bin/nix-build bootstrap/nix/var/nix/profiles/default/bin/nix-build
    ln -s ${bashInteractive}/bin/bash bootstrap/nix/var/nix/profiles/default/bin/bash
    ln -s ${cacert}/etc/ssl/certs/ca-bundle.crt bootstrap/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt

    ln -s ${coreutils}/bin/env bootstrap/root/usr/bin/env
    ln -s ${bashInteractive}/bin/bash bootstrap/root/bin/sh
    cp ${closure}/registration bootstrap/nix-termux/bootstrap.registration
    cat > bootstrap/root/etc/nix/nix.conf <<'EOF'
experimental-features = nix-command flakes
sandbox = false
build-users-group =
max-jobs = auto
substituters = https://cache.nixos.org/
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWw6OAkD9K2xYc0Y7M2e5mB3BfW7Q=
EOF

    tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -cf bootstrap.tar -C bootstrap .
    gzip -n bootstrap.tar

    sha256=$(sha256sum bootstrap.tar.gz | awk '{print $1}')
    url=${lib.escapeShellArg (if archiveUrl != null then archiveUrl else "nix-termux-bootstrap-${resolvedTermuxArch}.tar.gz")}
    jq -n \
      --arg url "$url" \
      --arg sha256 "$sha256" \
      --arg termuxArch ${lib.escapeShellArg resolvedTermuxArch} \
      --arg nixSystem ${lib.escapeShellArg system} \
      '{
        schemaVersion: 1,
        platform: {
          termuxArch: $termuxArch,
          nixSystem: $nixSystem
        },
        archive: {
          url: $url,
          sha256: $sha256
        },
        layout: {
          storeDir: "nix",
          rootDir: "root",
          nixBin: "nix/var/nix/profiles/default/bin/nix",
          registration: "nix-termux/bootstrap.registration"
        }
      }' > bootstrap.json

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp bootstrap.tar.gz "$out/nix-termux-bootstrap-${resolvedTermuxArch}.tar.gz"
    cp bootstrap.json "$out/nix-termux-bootstrap-${resolvedTermuxArch}.json"
    cp ${closure}/registration "$out/nix-termux-bootstrap-${resolvedTermuxArch}.registration"
    runHook postInstall
  '';

  meta = {
    description = "Bootstrap archive and manifest for nix-termux";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
