{ labConfig, ... }:

let
  namespacesList = builtins.attrValues labConfig.kubernetes.namespaces;
  namespacesResources = builtins.map
    (namespace: {
      namespace = {
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
      namespaces = namespacesResources;
    };
  };
}
