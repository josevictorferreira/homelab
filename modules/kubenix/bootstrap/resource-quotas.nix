{ homelab, ... }:

let
  inherit (homelab.kubernetes.namespaces) monitoring applications backup;

  # ResourceQuotas for namespaces
  resourceQuotas = {
    ${monitoring} = {
      metadata.name = monitoring;
      spec.hard = {
        "requests.cpu" = "2";
        "requests.memory" = "4Gi";
        "limits.cpu" = "4";
        "limits.memory" = "8Gi";
      };
    };
    ${applications} = {
      metadata.name = applications;
      spec.hard = {
        "requests.cpu" = "8";
        "requests.memory" = "16Gi";
        "limits.cpu" = "16";
        "limits.memory" = "32Gi";
      };
    };
    ${backup} = {
      metadata.name = backup;
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
