{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  app = "omniroute";
in
{
  submodules.instances."${app}" = {
    submodule = "release";
    args = {
      inherit namespace;
      image = {
        # OOM fix test build: release/v3.8.41 + heap-pressure chat admission + bounded
        # non-streaming response buffering (josevictorferreira/OmniRoute#1, OmniRoute #5152).
        # Revert to ghcr.io/diegosouzapw/omniroute once the fix lands upstream.
        repository = "ghcr.io/josevictorferreira/omniroute";
        tag = "3.8.41-oomfix2@sha256:f81ede8f8433a35d0f8b0dc34239154cdca89f126ad899e41d1df99de04be4b8";
        pullPolicy = "IfNotPresent";
      };
      secretName = "${app}-env";
      port = 20128;
      command = [
        "sh"
        "-ec"
        ''
          cd /app

          node --input-type=module <<'NODE'
          import fs from "node:fs";
          import path from "node:path";
          import Database from "better-sqlite3";

          const chunksDir = "/app/.build/next/server/chunks";
          const dbPath = "/app/data/storage.sqlite";

          function walk(dir) {
            if (!fs.existsSync(dir)) return [];
            const entries = fs.readdirSync(dir, { withFileTypes: true });
            const files = [];
            for (const entry of entries) {
              const file = path.join(dir, entry.name);
              if (entry.isDirectory()) files.push(...walk(file));
              else if (entry.isFile() && file.endsWith(".js")) files.push(file);
            }
            return files;
          }

          const responseBufferNeedle = 'let j="";await this.pipeSSE(i,b,a=>{j+=a.toString()});let k=this.now()-e;this.hookBufferUpdate(f,{status:i.status,responseHeaders:Object.fromEntries(i.headers.entries()),responseBody:j,responseSize:Buffer.byteLength(j),proxyLatencyMs:h-e,upstreamLatencyMs:k-(h-e)})';
          const responseBufferReplacement = 'await this.pipeSSE(i,b);let k=this.now()-e;this.hookBufferUpdate(f,{status:i.status,responseHeaders:Object.fromEntries(i.headers.entries()),responseBody:null,responseSize:0,proxyLatencyMs:h-e,upstreamLatencyMs:k-(h-e)})';
          const captureNeedle = 'shouldCaptureBody(){return!0}';
          const captureReplacement = 'shouldCaptureBody(){return!1}';

          let responseBufferPatches = 0;
          let capturePatches = 0;
          let remainingResponseBuffers = 0;

          for (const file of walk(chunksDir)) {
            const before = fs.readFileSync(file, "utf8");
            let after = before;

            const responseOccurrences = after.split(responseBufferNeedle).length - 1;
            if (responseOccurrences > 0) {
              after = after.split(responseBufferNeedle).join(responseBufferReplacement);
              responseBufferPatches += responseOccurrences;
            }

            const captureOccurrences = after.split(captureNeedle).length - 1;
            if (captureOccurrences > 0) {
              after = after.split(captureNeedle).join(captureReplacement);
              capturePatches += captureOccurrences;
            }

            remainingResponseBuffers += after.split(responseBufferNeedle).length - 1;
            if (after !== before) fs.writeFileSync(file, after);
          }

          if (remainingResponseBuffers > 0) {
            throw new Error("OmniRoute AgentBridge response buffering patch left unpatched call sites");
          }

          console.log("[omniroute-startup] response buffer patches=" + responseBufferPatches + " body capture patches=" + capturePatches);

          const comboNames = ["radagast", "mimo-v2.5", "pippin", "gandalf"];
          const logSettings = [
            ["databaseSettings", "logs.detailedLogsEnabled", false],
            ["databaseSettings", "logs.callLogPipelineEnabled", false],
            ["databaseSettings", "logs.maxDetailSizeKb", 10],
            ["databaseSettings", "logs.ringBufferSize", 100],
            ["databaseSettings", "detailedLogsEnabled", false],
            ["databaseSettings", "callLogPipelineEnabled", false],
            ["databaseSettings", "maxDetailSizeKb", 10],
            ["databaseSettings", "ringBufferSize", 100],
            ["settings", "detailed_logs_enabled", false],
            ["settings", "call_log_pipeline_enabled", false],
          ];

          function enforceDatabaseSettings() {
            if (!fs.existsSync(dbPath)) {
              console.log("[omniroute-startup] sqlite database not found; skipping config enforcement");
              return;
            }

            const db = new Database(dbPath);
            const deleteKey = db.prepare("DELETE FROM key_value WHERE namespace = ? AND key = ?");
            const insertKey = db.prepare("INSERT INTO key_value (namespace, key, value) VALUES (?, ?, ?)");
            const updateProviderConcurrency = db.prepare("UPDATE provider_connections SET max_concurrent = 1 WHERE is_active = 1 AND (max_concurrent IS NULL OR max_concurrent > 1)");
            const selectCombos = db.prepare("SELECT id, name, data FROM combos WHERE name IN (" + comboNames.map(() => "?").join(",") + ")");
            const updateCombo = db.prepare("UPDATE combos SET data = ?, updated_at = datetime('now') WHERE id = ?");

            const tx = db.transaction(() => {
              for (const [namespace, key, value] of logSettings) {
                deleteKey.run(namespace, key);
                insertKey.run(namespace, key, JSON.stringify(value));
              }

              const providerChanges = updateProviderConcurrency.run().changes;
              let comboChanges = 0;

              for (const row of selectCombos.all(...comboNames)) {
                let data = {};
                try {
                  data = JSON.parse(row.data || "{}");
                } catch {
                  data = {};
                }

                if (!data.config || typeof data.config !== "object" || Array.isArray(data.config)) {
                  data.config = {};
                }

                data.config.concurrencyPerModel = 1;
                data.config.queueDepth = 1;
                data.config.queueTimeoutMs = 10000;
                data.config.maxRetries = 0;

                updateCombo.run(JSON.stringify(data), row.id);
                comboChanges += 1;
              }

              console.log("[omniroute-startup] provider concurrency rows=" + providerChanges + " combo rows=" + comboChanges + " log settings=" + logSettings.length);
            });

            tx();
            db.close();
          }

          enforceDatabaseSettings();
          NODE

          exec node dev/run-standalone.mjs
        ''
      ];
      # EMERGENCY OOM stopgap (#5152): raised from 4Gi/1Gi. A 500K-token session turn
      # amplifies to ~2.7 GB on the pre-combo compression path and OOM-crashed the 3 GB
      # heap. Paired with the OMNIROUTE_MEMORY_MB=6144 env override in the rendered
      # Deployment so V8 can actually use this headroom. Revert once the source fix ships.
      resources = {
        limits = {
          cpu = "500m";
          memory = "8Gi";
        };
        requests = {
          cpu = "250m";
          memory = "2Gi";
        };
      };

      values = {
        controllers.main.strategy = "Recreate";
        controllers.main.pod.annotations."omniroute.josevictor.me/memory-mb" = "6144";
        controllers.main.pod.annotations."omniroute.josevictor.me/input-sanitizer" = "disabled";

        defaultPodOptions.imagePullSecrets = [
          { name = "ghcr-registry-secret"; }
        ];

        defaultPodOptions.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms =
          [
            {
              matchExpressions = [
                {
                  key = "kubernetes.io/hostname";
                  operator = "NotIn";
                  values = [ "lab-gamma-wk" ];
                }
              ];
            }
          ];

        controllers.main.pod.securityContext = {
          fsGroup = 1000;
          runAsUser = 1000;
          runAsGroup = 1000;
        };
        persistence.data = {
          enabled = true;
          type = "persistentVolumeClaim";
          storageClass = kubenix.lib.defaultStorageClass;
          size = "5Gi";
          accessMode = "ReadWriteOnce";
          globalMounts = [
            {
              path = "/app/data";
              readOnly = false;
            }
          ];
        };
        persistence.data-home = {
          enabled = true;
          type = "persistentVolumeClaim";
          storageClass = kubenix.lib.defaultStorageClass;
          size = "1Gi";
          accessMode = "ReadWriteOnce";
          globalMounts = [
            {
              path = "/app/data-home";
              readOnly = false;
            }
          ];
        };
      };
    };
  };
}
