{ homelab, ... }:

# Keeps the shared CephFS volume root at 2775 / gid 100.
#
# Why this exists: pods that mount `cephfs-shared-storage-root` set
# `fsGroup = 100`. With `fsGroupChangePolicy = "OnRootMismatch"` kubelet skips
# its ownership walk only when the volume ROOT already matches — and that check
# (`requiresPermissionChange`) compares the mode as well as the gid: it demands
# 0770 plus setgid. The root keeps drifting back to 0755, gid still correct at
# 100, which fails the mode half of the check and makes kubelet recursively
# chown the entire ~607k-entry tree on every single mount.
#
# That walk does not merely take a long time, it never finishes: hermes'
# SQLite sidecar files (`hermes/shared-state.db-shm`, `-wal`) are created and
# deleted constantly, so `filepath.Walk` eventually hits
# `lstat ...db-shm: no such file or directory`, the whole walk errors, and
# kubelet restarts it from the beginning. Pods sit in ContainerCreating /
# Init:0/1 forever with zero CSI calls, and the MDS gets hammered.
#
# It has recurred four times (2026-07-25, 08-18, 09-12, 09-18) and nothing has
# been identified that resets the mode, so guard the symptom: one `chmod` on a
# single inode is essentially free, and it turns a ~20 min manual recovery into
# a non-event.
#
# This job must NOT set fsGroup itself, or it would trigger the very walk it
# exists to prevent. It runs as the volume root's owner (uid 10000), which is
# enough for chmod.

let
  name = "shared-storage-root-mode-guard";
  namespace = homelab.kubernetes.namespaces.applications;

  # Only needs stat + chmod. Same tag the mautrix / home-assistant init
  # containers already use, so it is cached on the nodes.
  image = "busybox:1.37";

  mountPath = "/shared";
  expectedMode = "2775";

  script = ''
    set -eu
    mode=$(stat -c %a ${mountPath})
    gid=$(stat -c %g ${mountPath})
    if [ "$mode" = "${expectedMode}" ]; then
      echo "ok: ${mountPath} mode=$mode gid=$gid"
      exit 0
    fi
    echo "DRIFT: ${mountPath} mode=$mode gid=$gid, expected mode=${expectedMode}"
    chmod ${expectedMode} ${mountPath}
    echo "fixed: ${mountPath} now mode=$(stat -c %a ${mountPath}) gid=$(stat -c %g ${mountPath})"
  '';
in
{
  kubernetes.resources.cronJobs.${name} = {
    metadata = {
      inherit name namespace;
    };
    spec = {
      schedule = "*/10 * * * *";
      timeZone = homelab.timeZone;
      concurrencyPolicy = "Forbid";
      successfulJobsHistoryLimit = 1;
      failedJobsHistoryLimit = 3;
      jobTemplate.spec = {
        backoffLimit = 1;
        activeDeadlineSeconds = 120;
        template.spec = {
          restartPolicy = "OnFailure";
          # Deliberately no fsGroup here — see the header comment.
          securityContext = {
            runAsUser = 10000;
            runAsGroup = 100;
          };
          volumes = [
            {
              name = "shared-storage";
              persistentVolumeClaim.claimName = "cephfs-shared-storage-root";
            }
          ];
          containers = [
            {
              inherit name image;
              command = [
                "sh"
                "-c"
              ];
              args = [ script ];
              volumeMounts = [
                {
                  name = "shared-storage";
                  inherit mountPath;
                }
              ];
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities.drop = [ "ALL" ];
              };
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "64Mi";
                };
                limits = {
                  cpu = "100m";
                  memory = "64Mi";
                };
              };
            }
          ];
        };
      };
    };
  };
}
