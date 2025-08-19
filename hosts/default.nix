{ config, hostConfig, ... }:

let
  importProfiles =
    builtins.map (profile: "${homelab.paths.profiles}/${profile}.nix") hostConfig.roles;

  mkProfile = profileName: {
    name = profileName;
    value = { enable = true; };
  };

  profileAttrList = builtins.map mkProfile hostConfig.roles;
in
{
  imports =
    [ ./hardware/${hostConfig.machine}.nix ] ++ importProfiles;

  profiles = builtins.listToAttrs profileAttrList;
}
