{ ... }:

{
  kubernetes.resources = {
    serviceaccounts."kube-vip" = {
      metadata.namespace = "kube-system";
    };
    clusterroles."system:kube-vip-role" = {
      metadata.annotations."rbac.authorization.kubernetes.io/autoupdate" = "true";
      rules = [
        { apiGroups = [ "" ]; resources = [ "services/status" ]; verbs = [ "update" ]; }
        {
          apiGroups = [ "" ];
          resources = [ "services" "endpoints" ];
          verbs = [ "list" "get" "watch" "update" ];
        }
        {
          apiGroups = [ "" ];
          resources = [ "nodes" ];
          verbs = [ "list" "get" "watch" "update" "patch" ];
        }
        {
          apiGroups = [ "coordination.k8s.io" ];
          resources = [ "leases" ];
          verbs = [ "list" "get" "watch" "update" "create" ];
        }
        {
          apiGroups = [ "discovery.k8s.io" ];
          resources = [ "endpointslices" ];
          verbs = [ "list" "get" "watch" "update" ];
        }
        { apiGroups = [ "" ]; resources = [ "pods" ]; verbs = [ "list" ]; }
      ];
    };
    clusterrolebindings."system:kube-vip-binding" = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "system:kube-vip-role";
      };
      subjects = [{
        kind = "ServiceAccount";
        name = "kube-vip";
        namespace = "kube-system";
      }];
    };
  };
}
