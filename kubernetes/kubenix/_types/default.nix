{ kubenix, ... }:

{
  imports = with kubenix.modules; [
    k8s
  ];

  kubernetes = {
    customTypes = {
      clusterissuer = {
        attrName = "clusterissuer";
        group = "cert-manager.io";
        version = "v1";
        kind = "ClusterIssuer";
      };

      certificate = {
        attrName = "certificate";
        group = "cert-manager.io";
        version = "v1";
        kind = "Certificate";
      };

      ciliumloadbalancerippool = {
        attrName = "ciliumloadbalancerippool";
        group = "cilium.io";
        version = "v2alpha1";
        kind = "CiliumLoadBalancerIPPool";
      };

      ciliuml2announcementpolicy = {
        attrName = "ciliuml2announcementpolicy";
        group = "cilium.io";
        version = "v2alpha1";
        kind = "CiliumL2AnnouncementPolicy";
      };

      alertmanager = {
        attrName = "alertmanager";
        group = "monitoring.coreos.com";
        version = "v1";
        kind = "Alertmanager";
      };

      cephblockpool = {
        attrName = "cephblockpool";
        group = "ceph.rook.io";
        version = "v1";
        kind = "CephBlockPool";
      };

      cephcluster = {
        attrName = "cephcluster";
        group = "ceph.rook.io";
        version = "v1";
        kind = "CephCluster";
      };

      cephfilesystem = {
        attrName = "cephfilesystem";
        group = "ceph.rook.io";
        version = "v1";
        kind = "CephFilesystem";
      };

      cephfilesystemsubvolumegroup = {
        attrName = "cephfilesystemsubvolumegroup";
        group = "ceph.rook.io";
        version = "v1";
        kind = "CephFilesystemSubVolumeGroup";
      };

      cephobjectstore = {
        attrName = "cephobjectstore";
        group = "ceph.rook.io";
        version = "v1";
        kind = "CephObjectStore";
      };

      prometheus = {
        attrName = "prometheus";
        group = "monitoring.coreos.com";
        version = "v1";
        kind = "Prometheus";
      };

      prometheusrule = {
        attrName = "prometheusrule";
        group = "monitoring.coreos.com";
        version = "v1";
        kind = "PrometheusRule";
      };

      servicemonitor = {
        attrName = "servicemonitor";
        group = "monitoring.coreos.com";
        version = "v1";
        kind = "ServiceMonitor";
      };

      podmonitor = {
        attrName = "podmonitor";
        group = "monitoring.coreos.com";
        version = "v1";
        kind = "PodMonitor";
      };
    };
  };
}
