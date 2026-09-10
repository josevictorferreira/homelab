{ kubenix, homelab, ... }:

# Discord media retention.
#
# mautrix-discord re-uploads every Discord attachment, sticker and avatar onto
# tuwunel as *local* media, which is why it dominates the homeserver volume
# (21 GB of 24 GB when this job was written). WhatsApp, Slack and our own
# uploads are kept forever, so the blunt `media delete-range` command is
# unusable here: it has no per-user or per-room filter and would take those
# with it.
#
# The bridge's own `discord_file` table is the attribution source instead: one
# row per re-uploaded file, carrying the MXC URI and its upload timestamp. We
# select the rows past the retention window and hand exactly those MXC URIs to
# `!admin media delete-list`.
#
# Three stages, because no single image here has both psql and an HTTP client,
# and because the order matters: the media has to be gone before the rows that
# point at it are pruned. Everything under /work is written by the first stage,
# which runs as root; the curl stage only reads it.
let
  name = "tuwunel-media-retention";
  namespace = homelab.kubernetes.namespaces.applications;

  toolboxImage = "ghcr.io/josevictorferreira/backup-toolbox@sha256:08bda3ee3383b093cc0ed74d42ed9b167ecb92dd7c01e090a542d0a75dec8abb";
  curlImage = "curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69";

  retentionDays = "7";
  # Matrix caps a PDU at 65535 bytes. The binding constraint is not our command
  # (~53 B per MXC URI) but the log line tuwunel echoes back per deleted file
  # (~110 B). 400 keeps both sides well under the limit.
  batchSize = "400";
  # A batch of 400 takes tuwunel roughly a minute to work through, and admin
  # commands are processed one at a time. Pausing keeps us from queueing the
  # whole run ahead of the server.
  batchPause = "60";

  pgHost = kubenix.lib.serviceHostFor "postgresql-18-hl" namespace;
  homeserver = "http://${kubenix.lib.serviceHostFor "tuwunel" namespace}:8008";
  bridgeDatabase = "mautrix_discord_v2";
  # The server user, not a human admin: tuwunel honours its own commands only
  # while an emergency password is configured, which it is.
  adminUser = "conduit";
  adminRoomAlias = "#admins:${homelab.domain}";

  workDir = "/work";

  selectScript = ''
    set -euo pipefail

    CUTOFF=$(( ($(date +%s) - ${retentionDays} * 86400) * 1000 ))
    echo "$CUTOFF" > ${workDir}/cutoff
    echo "=== retention cutoff: $(date -d "@$((CUTOFF / 1000))") ==="

    psql -h "${pgHost}" -U postgres -d ${bridgeDatabase} -tAc \
      "select mxc from discord_file
       where timestamp < $CUTOFF and mxc like 'mxc://${homelab.domain}/%'" \
      | tr -d ' ' \
      | grep -E '^mxc://${homelab.domain}/[A-Za-z0-9_-]+$' \
      | sort -u > ${workDir}/targets.txt || true

    COUNT=$(wc -l < ${workDir}/targets.txt)
    echo "=== $COUNT files past retention ==="
    if [ "$COUNT" -eq 0 ]; then
      exit 0
    fi

    split -l ${batchSize} -d -a 4 ${workDir}/targets.txt ${workDir}/batch-
    for f in ${workDir}/batch-*; do
      jq -Rs '{msgtype:"m.text", body:("!admin media delete-list\n```\n" + . + "```")}' \
        < "$f" > "$f.json"
    done

    # Built here rather than in the curl stage: this image has jq, so the
    # password is escaped properly instead of pasted into a printf template.
    jq -n --arg pw "$EMERGENCY_PASSWORD" --arg user "${adminUser}" \
      '{type:"m.login.password", identifier:{type:"m.id.user", user:$user},
        password:$pw, initial_device_display_name:"${name}"}' \
      > ${workDir}/login.json

    echo "=== $(ls ${workDir}/batch-*.json | wc -l) batches prepared ==="
  '';

  deleteScript = ''
    set -eu

    if [ ! -s ${workDir}/targets.txt ]; then
      echo "=== nothing past retention, skipping ==="
      exit 0
    fi

    api() { curl -sS -f -m 120 -H "Content-Type: application/json" "$@"; }

    TOKEN=$(api -X POST --data-binary @${workDir}/login.json \
      "${homeserver}/_matrix/client/v3/login" 2>/dev/null \
      | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p' || true)
    if [ -z "$TOKEN" ]; then
      echo "FATAL: cannot log in as @${adminUser}. Is TUWUNEL_EMERGENCY_PASSWORD still set?" >&2
      exit 1
    fi
    trap 'curl -sS -m 30 -X POST -H "Authorization: Bearer $TOKEN" \
      -d "{}" "${homeserver}/_matrix/client/v3/logout" >/dev/null 2>&1 || true' EXIT

    ROOM=$(api -H "Authorization: Bearer $TOKEN" \
      "${homeserver}/_matrix/client/v3/directory/room/%23admins%3A${homelab.domain}" 2>/dev/null \
      | sed -n 's/.*"room_id":"\([^"]*\)".*/\1/p' || true)
    if [ -z "$ROOM" ]; then
      echo "FATAL: cannot resolve ${adminRoomAlias}" >&2
      exit 1
    fi

    TOTAL=$(ls ${workDir}/batch-*.json | wc -l)
    N=0
    for f in ${workDir}/batch-*.json; do
      N=$((N + 1))
      # tuwunel answers a large delete-list with "PDU exceeds 65535 bytes"
      # instead of the per-file log, and the deletion still runs, so the HTTP
      # status is the only thing that tells us the command was accepted.
      if ! api -X PUT -H "Authorization: Bearer $TOKEN" --data-binary @"$f" \
        "${homeserver}/_matrix/client/v3/rooms/$ROOM/send/m.room.message/${name}-$(date +%s)-$N" \
        > /dev/null; then
        echo "FATAL: batch $N/$TOTAL was rejected" >&2
        exit 1
      fi
      echo "=== batch $N/$TOTAL sent ==="
      sleep ${batchPause}
    done

    echo "=== all $TOTAL batches sent ==="
  '';

  pruneScript = ''
    set -euo pipefail

    if [ ! -s ${workDir}/targets.txt ]; then
      echo "=== nothing pruned ==="
      exit 0
    fi

    CUTOFF=$(cat ${workDir}/cutoff)
    # Drop the mappings whose media we just deleted, so a Discord URL posted
    # again is re-uploaded instead of resolving to a dead MXC forever.
    psql -h "${pgHost}" -U postgres -d ${bridgeDatabase} -c \
      "delete from discord_file where timestamp < $CUTOFF"
    echo "=== pruned discord_file rows older than cutoff ==="
  '';

  emergencyPasswordEnv = {
    name = "EMERGENCY_PASSWORD";
    valueFrom.secretKeyRef = {
      name = "tuwunel-env";
      key = "TUWUNEL_EMERGENCY_PASSWORD";
    };
  };

  pgPasswordEnv = {
    name = "PGPASSWORD";
    valueFrom.secretKeyRef = {
      name = "postgresql-auth";
      key = "admin-password";
    };
  };

  workMount = [
    {
      name = "work";
      mountPath = workDir;
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
      cpu = "200m";
      memory = "256Mi";
    };
  };
in
{
  kubernetes.resources.cronJobs.${name} = {
    metadata = {
      inherit name namespace;
    };
    spec = {
      schedule = "20 4 * * *";
      timeZone = homelab.timeZone;
      concurrencyPolicy = "Forbid";
      successfulJobsHistoryLimit = 3;
      failedJobsHistoryLimit = 3;
      jobTemplate.spec = {
        backoffLimit = 1;
        # The first run has a backlog to clear, which is far more batches
        # than the steady-state handful.
        activeDeadlineSeconds = 7200;
        template.spec = {
          restartPolicy = "OnFailure";
          imagePullSecrets = [ { name = "ghcr-registry-secret"; } ];
          volumes = [
            {
              name = "work";
              emptyDir = { };
            }
          ];
          initContainers = [
            {
              name = "select";
              image = toolboxImage;
              command = [
                "bash"
                "-c"
              ];
              args = [ selectScript ];
              env = [
                pgPasswordEnv
                emergencyPasswordEnv
              ];
              volumeMounts = workMount;
              inherit resources securityContext;
            }
            {
              name = "delete-media";
              image = curlImage;
              command = [
                "sh"
                "-c"
              ];
              args = [ deleteScript ];
              volumeMounts = workMount;
              inherit resources securityContext;
            }
          ];
          containers = [
            {
              name = "prune-rows";
              image = toolboxImage;
              command = [
                "bash"
                "-c"
              ];
              args = [ pruneScript ];
              env = [ pgPasswordEnv ];
              volumeMounts = workMount;
              inherit resources securityContext;
            }
          ];
        };
      };
    };
  };
}
