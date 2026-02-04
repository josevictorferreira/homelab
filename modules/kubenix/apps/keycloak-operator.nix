{
  lib,
  kubenix,
  homelab,
  ...
}:

let
  app = "keycloak";
  namespace = homelab.kubernetes.namespaces.applications;
  domain = "keycloak.${homelab.domain}";
in
{
  kubernetes = {
    # Keycloak Operator deployment using raw manifests
    resources = {
      # Operator ServiceAccount
      serviceAccounts."keycloak-operator" = {
        metadata = {
          name = "keycloak-operator";
          namespace = namespace;
        };
      };

      # Operator Deployment
      deployments."keycloak-operator" = {
        metadata = {
          name = "keycloak-operator";
          namespace = namespace;
        };
        spec = {
          replicas = 1;
          selector = {
            matchLabels = {
              name = "keycloak-operator";
            };
          };
          template = {
            metadata = {
              labels = {
                name = "keycloak-operator";
              };
            };
            spec = {
              serviceAccountName = "keycloak-operator";
              containers = [
                {
                  name = "keycloak-operator";
                  image = "quay.io/keycloak/keycloak-operator:25.0";
                  env = [
                    {
                      name = "WATCH_NAMESPACE";
                      value = "";
                    }
                    {
                      name = "POD_NAME";
                      valueFrom = {
                        fieldRef = {
                          fieldPath = "metadata.name";
                        };
                      };
                    }
                    {
                      name = "OPERATOR_NAME";
                      value = "keycloak";
                    }
                  ];
                }
              ];
            };
          };
        };
      };
    };
  };
}
