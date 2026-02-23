{ pkgs, lib, ... }:

let
  # Download prism-media package directly from npm
  prismMedia = pkgs.fetchurl {
    url = "https://registry.npmjs.org/prism-media/-/prism-media-1.3.5.tgz";
    sha256 = "sha256-ywkjKPUMb40pp+ePHMC+X0E3PI657t+f8zZHhOMBtDI=";
  };
in
{
  inherit prismMedia;
}
