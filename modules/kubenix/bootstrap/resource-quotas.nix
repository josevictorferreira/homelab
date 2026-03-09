{ homelab, ... }:

let
  inherit (homelab.kubernetes.namespaces) monitoring applications backup;

  # ResourceQuotas for namespaces
  resourceQuotas = {
    ${monitoring} = {
      metadata.name = monitoring;
      metadata.namespace = monitoring;
      spec.hard = {
        "requests.cpu" = "4";
        "requests.memory" = "8Gi";
        "limits.cpu" = "8";
        "limits.memory" = "16Gi";
      };
    };
    ${applications} = {
      metadata.name = applications;
      metadata.namespace = applications;
      spec.hard = {
        "requests.cpu" = "12";
        "requests.memory" = "24Gi";
        "limits.cpu" = "24";
        "limits.memory" = "48Gi";
      };
    };
    ${backup} = {
      metadata.name = backup;
      metadata.namespace = backup;
      spec.hard = {
        "requests.cpu" = "1";
        "requests.memory" = "2Gi";
        "limits.cpu" = "2";
        "limits.memory" = "4Gi";
      };
    };
  };

  # LimitRange - default resource constraints for pods without explicit limits
  limitRanges = {
    ${monitoring} = {
      metadata.name = "default-limits";
      metadata.namespace = monitoring;
      spec.limits = [
        {
          type = "Container";
          default = {
            cpu = "500m";
            memory = "512Mi";
          };
          defaultRequest = {
            cpu = "100m";
            memory = "128Mi";
          };
          max = {
            cpu = "2";
            memory = "4Gi";
          };
          min = {
            cpu = "50m";
            memory = "64Mi";
          };
        }
      ];
    };
    ${applications} = {
      metadata.name = "default-limits";
      metadata.namespace = applications;
      spec.limits = [
        {
          type = "Container";
          default = {
            cpu = "500m";
            memory = "512Mi";
          };
          defaultRequest = {
            cpu = "100m";
            memory = "128Mi";
          };
          max = {
            cpu = "2";
            memory = "4Gi";
          };
          min = {
            cpu = "50m";
            memory = "64Mi";
          };
        }
      ];
    };
    ${backup} = {
      metadata.name = "default-limits";
      metadata.namespace = backup;
      spec.limits = [
        {
          type = "Container";
          default = {
            cpu = "250m";
            memory = "256Mi";
          };
          defaultRequest = {
            cpu = "100m";
            memory = "128Mi";
          };
          max = {
            cpu = "1";
            memory = "2Gi";
          };
          min = {
            cpu = "50m";
            memory = "64Mi";
          };
        }
      ];
    };
  };

in
{
  kubernetes.resources = {
    resourceQuotas = resourceQuotas;
    limitRanges = limitRanges;
  };
}
