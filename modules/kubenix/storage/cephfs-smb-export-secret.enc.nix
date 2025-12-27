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
          namespace = namespace;
        };
        data = {
          "userID" = kubenix.lib.secretsFor "cephfs_user_id";
          "userKey" = kubenix.lib.secretsFor "cephfs_user_key";
        };
      };

      configMaps."${appName}-config" = {
        metadata = {
          name = "${appName}-config";
          namespace = namespace;
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
