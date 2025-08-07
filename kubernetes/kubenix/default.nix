{ kubenix, ... }:

{
  imports = [ kubenix.modules.k8s ];

  kubernetes.resources.pods = {
    example.spec.containers = {
      ex.image = "nginx";
    };
  };
}
