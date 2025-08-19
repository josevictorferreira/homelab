{ labConfig, hostConfig, ... }:

let

  importProfiles =
    builtins.map (profile: "${labConfig.project.paths.profiles}/${profile}.nix") hostConfig.roles;

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
