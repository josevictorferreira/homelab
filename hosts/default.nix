{ hostConfig, lib, rolesPath, ... }:

let

  importRoles =
    builtins.map (role: "${rolesPath}/${role}.nix") hostConfig.roles;

  capitalize =
    (s:
      if s == "" then ""
      else
        let
          head = lib.strings.toUpper (builtins.substring 0 1 s);
          tail = builtins.substring 1 ((builtins.stringLength s) - 1) s;
        in
        "${head}${tail}");

  toLowerCamelCase =
    (s:
      let
        parts = lib.splitString "-" s;
        first = lib.strings.toLower (builtins.head parts);
        rest = map capitalize (builtins.tail parts);
      in
      lib.concatStringsSep "" ([ first ] ++ rest));

  mkRole = roleName: {
    name = toLowerCamelCase roleName;
    value = { enable = true; };
  };

  roleAttrList = builtins.map mkRole hostConfig.roles;
in
{
  imports =
    [ ./hardware/${hostConfig.machine}.nix ] ++ importRoles;

  roles = builtins.listToAttrs roleAttrList;
}
