{ lib, hostConfig, rolesPath, ... }:

let
  importRoles = builtins.map (role: "${rolesPath}/${role}.nix") hostConfig.roles;
  mkRole = (roleName: {
    name = lib.toCamelCase roleName;
    enable = true;
  });
  mkRoles = builtins.map mkRole hostConfig.roles;
in
{
  imports = [
    "./hardware/${hostConfig.machine}.nix"
  ] ++ importRoles;
  roles = builtins.listToAttrs (mkRoles hostConfig.roles);
}
