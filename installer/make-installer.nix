{ stdenvNoCC
, coreutils
}:

stdenvNoCC.mkDerivation {
  pname = "nix-termux-installer";
  version = "0.1.0";
  src = ./..;

  nativeBuildInputs = [ coreutils ];
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    install -Dm755 installer/install.sh "$out/install.sh"
    (cd "$out" && sha256sum install.sh > install.sh.sha256)
    runHook postInstall
  '';
}
