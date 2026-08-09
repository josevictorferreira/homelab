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

  # Git credentials for coding tasks run in the sandbox.  Both names are the
  # same token: git/most tooling reads GITHUB_TOKEN, the gh CLI prefers
  # GH_TOKEN.  Mirrors the pair already set on hermes-agent-env.
  kubernetes.resources.secrets."${name}-env" = {
    metadata.namespace = namespace;
    stringData = {
      GITHUB_TOKEN = kubenix.lib.secretsFor "github_token";
      GH_TOKEN = kubenix.lib.secretsFor "github_token";
    };
  };
}
