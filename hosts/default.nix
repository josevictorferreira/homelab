{ hostConfig, lib, rolesPath, ... }:

let

  importRoles =
    builtins.map (role: "${rolesPath}/${role}.nix") hostConfig.roles;

  mkRole = roleName: {
    name = lib.strings.toLowerCamelCase roleName;
    value = { enable = true; };
  };

  roleAttrList = builtins.map mkRole hostConfig.roles;
in
{
  imports =
    [ ./hardware/${hostConfig.machine}.nix ] ++ importRoles;

  roles = builtins.listToAttrs roleAttrList;
}
