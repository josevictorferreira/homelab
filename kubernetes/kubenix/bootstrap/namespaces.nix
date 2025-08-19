{ homelab, ... }:

let
  namespacesList = builtins.attrValues homelab.kubernetes.namespaces;
  namespacesResources = builtins.map
    (namespace: {
      name = namespace;
      value = {
        metadata = {
          name = namespace;
        };
      };
    })
    namespacesList;
in
{
  kubernetes = {
    resources = {
      namespaces = builtins.listToAttrs namespacesResources;
    };
  };
}
