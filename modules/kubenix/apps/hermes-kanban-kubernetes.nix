# hermes-kanban-kubernetes: one Kubernetes Job per Hermes Kanban task run.
#
# Runs a standalone controller (own ServiceAccount + namespaced Job RBAC) that
# calls Hermes `dispatch_once(spawn_fn=<k8s launcher>)`. Requires disabling the
# in-gateway dispatcher in the live Hermes config:
#
#     kanban:
#       dispatch_in_gateway: false
#
# DO NOT flip that until the plugin's contract tests pass against this exact
# Hermes image (esp. the decomposition check — the gateway loop also runs
# auto_decompose/orchestrator). See the plugin repo's HOMELAB_RUNBOOK.md.
#
# Wheel delivery: runtime pip-bootstrap from the PVC (same pattern as the
# gateway's faster-whisper/mautrix/hindsight-client installs). Drop the wheel at
#   ~/Homelab/hermes/.plugins/hermes-kanban-kubernetes/*.whl   (= /opt/data/.plugins/...)
# before scaling the controller up.
{ kubenix, homelab, ... }:

let
  name = "hermes-kanban-kubernetes";
  namespace = homelab.kubernetes.namespaces.applications;
  # Keep in lockstep with modules/kubenix/apps/hermes-agent.nix.
  image = "docker.io/nousresearch/hermes-agent:v2026.6.19@sha256:9f367c7756ef087661a361536a89f438d57a122b958dc23d82d456b1433e6e9e";
  pvc = kubenix.lib.sharedStorage.rootPVC;
  board = "omniroute-plugin";

  controllerSA = "hermes-kanban-controller";
  workerSA = "hermes-kanban-worker";
  configPath = "/etc/hermes-kanban-kubernetes/config.yaml";
  wheelDir = "/opt/data/.plugins/hermes-kanban-kubernetes";
  userSite = "/opt/data/.local/lib/python3.13/site-packages";

  # Plugin config (no secrets). Mirrors the repo's deploy/examples/config.yaml.
  launcherConfig = ''
    apiVersion: hermes-kanban-kubernetes/v1alpha1
    kind: LauncherConfig
    controller:
      namespace: ${namespace}
      jobNamePrefix: hk
      dispatchIntervalSeconds: 60
      reconcileIntervalSeconds: 30
      maxActiveJobs: 1
      maxActiveJobsPerProfile: 1
      claimTtlSeconds: 900
      handleStore: file
    compatibility:
      hermesVersion: "2026.6.19"
      failOnUnknownHermesVersion: true
      requireRemoteLifecycleContract: true
    job:
      image: ${image}
      serviceAccountName: ${workerSA}
      backoffLimit: 0
      activeDeadlineSeconds: 7200
      ttlSecondsAfterFinished: 86400
      resources:
        default:
          requests: { cpu: 500m, memory: 1Gi, ephemeral-storage: 5Gi }
          limits:   { cpu: "2",  memory: 4Gi, ephemeral-storage: 20Gi }
      securityContext:
        runAsUser: 10000
        runAsGroup: 2002
        fsGroup: 2002
        seccompProfile: RuntimeDefault
        readOnlyRootFilesystem: false
      # Worker imports Hermes (venv) + the plugin (shared user-site + PYTHONPATH).
      workerCommand:
        - /opt/hermes/.venv/bin/python
        - -m
        - hermes_kanban_kubernetes.worker
      extraEnv:
        PYTHONPATH: ${userSite}
        PYTHONUSERBASE: /opt/data/.local
    storage:
      mode: split
      pvcName: ${pvc}
      profileSubPathTemplate: hermes/profiles/{profile}
      profileMountPathTemplate: /opt/data/profiles/{profile}
      kanbanStateSubPathTemplate: hermes/kanban/boards/{board}
      kanbanStateMountPath: /opt/data/kanban/boards/{board}
      workspacesSubPath: hermes/kanban/workspaces
      workspacesMountPath: /opt/data/kanban/workspaces
      launchSubPathTemplate: hermes/kanban/.launches/{run_hash}
      launchMountPath: /run/hermes-kanban
      managedConfigFileSubPath: hermes/managed/config.yaml
      managedConfigMountPath: /opt/data/managed
      extraMounts:
        - name: user-site
          subPath: hermes/.local
          mountPath: /opt/data/.local
          readOnly: true
      allowBroadDataRootMount: false
    profiles:
      allowed:
        - valygar
      secretEnv:
        valygar:
          - envName: GITHUB_TOKEN
            secretName: hermes-agent-env
            secretKey: GITHUB_TOKEN
          - envName: GH_TOKEN
            secretName: hermes-agent-env
            secretKey: GH_TOKEN
    observability:
      logFormat: json
      emitKubernetesEvents: true
      includeTaskText: false
  '';

  # Bootstrap uses system pip --user (installs into /opt/data/.local, on
  # PYTHONPATH) exactly like the gateway, then runs the controller with the venv
  # python so Hermes (venv) + plugin/kubernetes-client (user-site) are both importable.
  controllerCmd = ''
    umask 0002
    if ! ls ${wheelDir}/*.whl >/dev/null 2>&1; then
      echo "FATAL: no plugin wheel in ${wheelDir}; build+copy it before scaling up" >&2
      exit 78
    fi
    pip install --user --no-warn-script-location ${wheelDir}/*.whl >&2
    exec /opt/hermes/.venv/bin/python -m hermes_kanban_kubernetes.controller
  '';
in
{
  kubernetes.resources.configMaps."${name}-config" = {
    metadata = {
      name = "${name}-config";
      inherit namespace;
    };
    data."config.yaml" = launcherConfig;
  };

  kubernetes.resources.serviceAccounts."${controllerSA}" = {
    metadata = {
      name = controllerSA;
      inherit namespace;
    };
  };

  # Worker identity: no RoleBinding, token never mounted.
  kubernetes.resources.serviceAccounts."${workerSA}" = {
    metadata = {
      name = workerSA;
      inherit namespace;
    };
    automountServiceAccountToken = false;
  };

  kubernetes.resources.roles."${controllerSA}" = {
    metadata = {
      name = controllerSA;
      inherit namespace;
    };
    rules = [
      {
        apiGroups = [ "batch" ];
        resources = [ "jobs" ];
        verbs = [ "create" "get" "list" "watch" "delete" ];
      }
      {
        apiGroups = [ "" ];
        resources = [ "pods" ];
        verbs = [ "get" "list" "watch" ];
      }
      {
        apiGroups = [ "" ];
        resources = [ "pods/log" ];
        verbs = [ "get" ];
      }
      {
        apiGroups = [ "" ];
        resources = [ "events" ];
        verbs = [ "create" "patch" ];
      }
    ];
  };

  kubernetes.resources.roleBindings."${controllerSA}" = {
    metadata = {
      name = controllerSA;
      inherit namespace;
    };
    subjects = [
      {
        kind = "ServiceAccount";
        name = controllerSA;
        inherit namespace;
      }
    ];
    roleRef = {
      kind = "Role";
      name = controllerSA;
      apiGroup = "rbac.authorization.k8s.io";
    };
  };

  kubernetes.resources.deployments."${name}-controller" = {
    metadata = {
      name = "${name}-controller";
      inherit namespace;
      labels = {
        app = name;
        component = "controller";
      };
    };
    spec = {
      # Start at 0: scale to 1 only after the wheel is on the PVC, contract tests
      # pass, and kanban.dispatch_in_gateway is set false. Single-active only.
      replicas = 0;
      strategy.type = "Recreate";
      selector.matchLabels = {
        app = name;
        component = "controller";
      };
      template = {
        metadata.labels = {
          app = name;
          component = "controller";
        };
        spec = {
          serviceAccountName = controllerSA;
          securityContext.supplementalGroups = [ 100 ];
          terminationGracePeriodSeconds = 60;
          imagePullSecrets = [ { name = "ghcr-registry-secret"; } ];
          containers = [
            {
              name = "controller";
              inherit image;
              imagePullPolicy = "IfNotPresent";
              command = [ "/bin/sh" "-c" controllerCmd ];
              env = [
                { name = "HOME"; value = "/opt/data"; }
                { name = "HERMES_KANBAN_KUBERNETES_CONFIG"; value = configPath; }
                { name = "HERMES_KANBAN_DB"; value = "/opt/data/kanban/boards/${board}/kanban.db"; }
                { name = "HERMES_KANBAN_BOARD"; value = board; }
                { name = "HERMES_KANBAN_WORKSPACES_ROOT"; value = "/opt/data/kanban/workspaces"; }
                # Launch envelopes are written PVC-root-relative (worker subPaths
                # include the "hermes/" prefix), so point the launch root at the
                # PVC root mount below — NOT at /opt/data (=<pvc>/hermes).
                { name = "HERMES_KANBAN_LAUNCH_ROOT"; value = "/pvc-root"; }
                { name = "HERMES_KANBAN_HANDLE_DIR"; value = "/opt/data/kanban/.k8s-handles"; }
                { name = "PYTHONUSERBASE"; value = "/opt/data/.local"; }
                { name = "PYTHONPATH"; value = userSite; }
                { name = "PIP_USER"; value = "true"; }
                { name = "PIP_REQUIRE_VIRTUALENV"; value = "false"; }
                {
                  name = "PATH";
                  value = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin";
                }
              ];
              volumeMounts = [
                { name = "hermes-data"; mountPath = "/opt/data"; subPath = "hermes"; }
                # PVC root, so the controller can write launch envelopes at the
                # exact PVC-relative paths the worker Jobs later mount.
                { name = "hermes-data"; mountPath = "/pvc-root"; }
                { name = "config"; mountPath = "/etc/hermes-kanban-kubernetes"; readOnly = true; }
              ];
              resources = {
                requests = { cpu = "50m"; memory = "256Mi"; };
                limits = { cpu = "500m"; memory = "512Mi"; };
              };
              securityContext = {
                runAsNonRoot = true;
                runAsUser = 10000;
                runAsGroup = 2002;
                allowPrivilegeEscalation = false;
                capabilities.drop = [ "ALL" ];
              };
            }
          ];
          volumes = [
            { name = "hermes-data"; persistentVolumeClaim.claimName = pvc; }
            { name = "config"; configMap.name = "${name}-config"; }
          ];
        };
      };
    };
  };
}
