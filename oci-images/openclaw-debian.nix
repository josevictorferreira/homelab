{ pkgs, lib }:

let
  baseImage = pkgs.dockerTools.pullImage {
    imageName = "ghcr.io/openclaw/openclaw";
    imageDigest = "sha256:5ea30d02a706c49795ed0a3c1526dec51ed90107a6859e93bf27a663105d1c28";
    sha256 = "sha256-EPiQ6YZM2ATYqay1uMUBeL/PJP4KwNyGL2U2plPqGG0=";
  };

  losslessClawVersion = "0.10.0";
  losslessClawSource = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@martian-engineering/lossless-claw/-/lossless-claw-${losslessClawVersion}.tgz";
    sha256 = "sha256-1q/YTpgT4Jcc/yFPuwLjq6MhlG+SGzcbguIzkd8BFgI=";
  };

  toolPkgs = [
    pkgs.jq
    pkgs.ffmpeg-headless
    pkgs.imagemagick
    pkgs.ripgrep
    pkgs.gh
    pkgs.obsidian
    pkgs.typst
    pkgs.tree
    pkgs.which
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.coreutils
    (pkgs.python3.withPackages (ps: [ ps.pip ]))
    pkgs.uv
    pkgs.file
    pkgs.diffutils
    pkgs.gzip
    pkgs.openssh
    pkgs.rsync
    pkgs.less
    pkgs.gnutar
    pkgs.fontconfig
  ];

  fontPkgs = [
    pkgs.dejavu_fonts
    pkgs.noto-fonts
    pkgs.noto-fonts-color-emoji
    pkgs.noto-fonts-cjk-sans
    pkgs.liberation_ttf
    pkgs.font-awesome
  ];

  allPkgs = toolPkgs ++ fontPkgs;

  toolsEnv = pkgs.buildEnv {
    name = "openclaw-tools-env";
    paths = allPkgs;
    pathsToLink = [
      "/lib"
      "/share"
    ];
  };

  toolsRoot = pkgs.runCommand "openclaw-tools-root" { } ''
    mkdir -p $out/usr/local/bin $out/usr/local/lib $out/usr/local/share/fonts

    for pkg in ${lib.concatMapStringsSep " " toString allPkgs}; do
      if [ -d "$pkg/bin" ]; then
        for f in "$pkg/bin/"*; do
          [ -e "$f" ] || continue
          name=$(basename "$f")
          [ -e "$out/usr/local/bin/$name" ] && continue
          ln -s "$f" "$out/usr/local/bin/$name"
        done
      fi
    done

    for pkg in ${lib.concatMapStringsSep " " toString fontPkgs}; do
      if [ -d "$pkg/share/fonts" ]; then
        cp -rL "$pkg/share/fonts/"* "$out/usr/local/share/fonts/" 2>/dev/null || true
      fi
      if [ -d "$pkg/lib/X11/fonts" ]; then
        cp -rL "$pkg/lib/X11/fonts/"* "$out/usr/local/share/fonts/" 2>/dev/null || true
      fi
    done

    if [ -d "${toolsEnv}/lib" ]; then
      cp -rs "${toolsEnv}/lib/"* "$out/usr/local/lib/" 2>/dev/null || true
    fi
    if [ -d "${toolsEnv}/share" ]; then
      mkdir -p "$out/usr/local/share"
      for d in "${toolsEnv}/share/"*; do
        name=$(basename "$d")
        [ "$name" = "fonts" ] && continue
        if [ -e "$out/usr/local/share/$name" ] && [ -d "$d" ]; then
          cp -rs "$d/"* "$out/usr/local/share/$name/" 2>/dev/null || true
        else
          cp -rs "$d" "$out/usr/local/share/$name" 2>/dev/null || true
        fi
      done
    fi
  '';

in
pkgs.dockerTools.buildImage {
  name = "localhost/openclaw-debian";
  tag = "2026.5.18-luna-hindsight";
  fromImage = baseImage;
  copyToRoot = [
    toolsRoot
  ];
  extraCommands = ''
    mkdir -p ./usr/local/share/fonts
    ${pkgs.fontconfig}/bin/fc-cache -f ./usr/local/share/fonts 2>/dev/null || true
  '';
  config = {
    Env = [
      "PATH=/home/node/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    ];
  };
}
