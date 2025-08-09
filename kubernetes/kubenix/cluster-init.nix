{ kubenix, ... }:

let
  namespaces = [
    "apps"
    "monitoring"
  ];
in
{
  imports = with kubenix.modules; [
    helm
    k8s
  ];

  kubernetes.resources = {
    namespace = builtins.listToAttrs (map
      (ns: {
        name = ns;
        value = {
          metadata = {
            name = ns;
          };
        };
      })
      namespaces);
  };
}
