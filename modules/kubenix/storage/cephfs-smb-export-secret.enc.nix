{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.storage;
  appName = "cephfs-smb-export";
in
{
  kubernetes = {
    resources = {
      secrets."cephfs-user-secret" = {
        metadata = {
          inherit namespace;
        };
        data = {
          "userID" = kubenix.lib.secretsFor "cephfs_user_id";
          "userKey" = kubenix.lib.secretsFor "cephfs_user_key";
        };
      };

      configMaps."${appName}-config" = {
        metadata = {
          name = "${appName}-config";
          inherit namespace;
        };
        data."config.yml" = ''
          auth:
            - user: homelab
              group: homelab
              uid: 2002
              gid: 2002
              password: ${kubenix.lib.secretsFor "cephfs_smb_export_password"}

          global:
            - "server min protocol = SMB2"
            - "server max protocol = SMB3"
            - "map to guest = Bad User"
            - "ea support = yes"
            - "vfs objects = fruit streams_xattr"
            - "fruit:metadata = stream"
            - "fruit:model = MacSamba"
            - "inherit permissions = yes"
            - "create mask = 0664"
            - "directory mask = 0775"
            - "force user = homelab"
            - "force group = homelab"
            # hermes re-locks its profile HOMEs to 0700 (owned by uid
            # 10000) at runtime, which a forced uid-2002 session cannot
            # traverse. admin users bypasses Unix perm checks for this
            # login so every profile folder stays reachable. Must live in
            # global: the crazy-max/samba image ignores per-share extra:.
            - "admin users = homelab"

          share:
            - name: homelab-smb
              path: /samba/share
              browsable: yes
              readonly: no
              guestok: no
              veto: no
              extra:
                - "force user = homelab"
                - "force group = homelab"
                - "create mask = 0664"
                - "directory mask = 0775"
        '';
      };
    };
  };
}
