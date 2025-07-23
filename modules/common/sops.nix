{ config, username, flakeRoot, ... }:

let
  userHomeDir = config.users.users.${username}.home;
  ageKeyFilePath = "${userHomeDir}/.config/sops/age/keys.txt";
in
{
  sops = {
    defaultSopsFile = "${flakeRoot}/secrets/secrets.enc.yaml";
    age.keyFile = ageKeyFilePath;
  };

  sops.secrets."k3s_token" = {
    owner = config.users.users.${username}.name;
    mode = "0400";
  };

  environment.variables.SOPS_AGE_KEY_FILE = ageKeyFilePath;
}
