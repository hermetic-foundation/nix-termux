{ stdenvNoCC
, coreutils
, gnutar
, gzip
}:

stdenvNoCC.mkDerivation {
  pname = "nix-termux-runtime";
  version = "0.1.0";
  src = ./..;

  nativeBuildInputs = [
    coreutils
    gnutar
    gzip
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p archive/bin archive/installer archive/runtime archive/docs archive/bootstrap archive/tests/termux
    install -Dm755 bin/nix-termux archive/bin/nix-termux
    install -Dm755 installer/install.sh archive/installer/install.sh
    install -Dm755 installer/uninstall.sh archive/installer/uninstall.sh
    install -Dm755 runtime/nix-termux.sh archive/runtime/nix-termux.sh
    install -Dm644 LICENSE archive/LICENSE
    install -Dm644 README.md archive/README.md
    cp -R docs/. archive/docs/
    cp -R bootstrap/*.json archive/bootstrap/
    install -Dm755 tests/termux/device-smoke.sh archive/tests/termux/device-smoke.sh

    tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -cf nix-termux-runtime.tar -C archive .
    gzip -n nix-termux-runtime.tar

    mkdir -p "$out"
    cp nix-termux-runtime.tar.gz "$out/nix-termux-runtime.tar.gz"
    (cd "$out" && sha256sum nix-termux-runtime.tar.gz > nix-termux-runtime.tar.gz.sha256)

    runHook postInstall
  '';
}
