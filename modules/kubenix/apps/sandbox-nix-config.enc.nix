{ kubenix, homelab, ... }:

let
  name = "sandbox-nix";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."${name}-ssh" = {
    metadata.namespace = namespace;
    stringData = {
      # Public key is mounted as authorized_keys so the private key owner
      # (hermes agents) can authenticate.
      "authorized_keys" = kubenix.lib.secretsFor "sandbox_nix_ssh_public_key";
    };
  };
}
