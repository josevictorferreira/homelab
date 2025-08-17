{ loadBalancer, ... }:

let
  self = {
    serviceIpFor = serviceName: {
      "lbipam.cilium.io/ips" = loadBalancer.services.${serviceName};
      "lbipam.cilium.io/sharing-key" = serviceName;
    };
  };
in
self
