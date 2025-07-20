# FMJ Studios - Linkwarden Helm Chart <img src="https://raw.githubusercontent.com/linkwarden/linkwarden/4640c1c966d37b7fc22e4ebfcb244d03da1d6d82/assets/logo.png" alt="Linkwarden Logo" width="175" height="175" align="right" loading="lazy">

Linkwarden is a self-hosted, open-source collaborative bookmark manager to collect, organize and archive web pages. The
objective is to organize useful web pages and articles you find across the web in one place, and since useful web pages
can go away (see the inevitability of Link Rot), Linkwarden also saves a copy of each web page as a Screenshot and PDF,
ensuring accessibility even if the original content is no longer available.

Additionally, Linkwarden is designed with collaboration in mind, sharing links with the public and/or allowing multiple
users to work together seamlessly.

It delivers all of these features within a single Docker image available on
the [GitHub Container Registry](https://github.com/linkwarden/linkwarden/pkgs/container/linkwarden).

> Head to the [Linkwarden GitHub Repository](https://github.com/linkwarden/linkwarden) or
> their [Website](https://linkwarden.app/) for in-depth [documentation](https://docs.linkwarden.app/)
> and [configuration guides](https://docs.linkwarden.app/self-hosting/environment-variables).

## ✨ TL;DR

### Helm Repository Installation

```shell
helm repo add fmjstudios https://fmjstudios.github.io/helm
helm install linkwarden fmjstudios/linkwarden --version X.Y.Z
```

### OCI Installation

```shell
helm install oci://ghcr.io/fmjstudios/helm/linkwarden:X.Y.Z
```

## Introduction

This chart bootstraps a Linkwarden [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
on
a [Kubernetes](https://kubernetes.io) cluster using the [Helm](https://helm.sh/) package manager. For cluster networking
a [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
and [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) manifest is also created, whereas the
Ingress needs to be explicitly enabled. Lastly the chart configures
a [PodDisruptionBudget](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) if
enabled. [RBAC manifests](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) are enabled by default.

The chart supports the configuration of
all [Linkwarden environment variables](https://docs.linkwarden.app/self-hosting/environment-variables)
via the `linkwarden` key in Helm's _values_ and makes use of the official Docker Hub container image, although this is
configurable via the Image
Parameters.

## Parameters

### Image parameters

| Name                | Description                                                         | Value                   |
| ------------------- | ------------------------------------------------------------------- | ----------------------- |
| `image.registry`    | The Docker registry to pull the image from                          | `ghcr.io`               |
| `image.repository`  | The registry repository to pull the image from                      | `linkwarden/linkwarden` |
| `image.tag`         | The image tag to pull                                               | `v2.5.3`                |
| `image.digest`      | The image digest to pull                                            | `""`                    |
| `image.pullPolicy`  | The Kubernetes image pull policy                                    | `IfNotPresent`          |
| `image.pullSecrets` | A list of secrets to use for pulling images from private registries | `[]`                    |

### Name overrides

| Name               | Description                                      | Value |
| ------------------ | ------------------------------------------------ | ----- |
| `nameOverride`     | String to partially override linkwarden.fullname | `""`  |
| `fullnameOverride` | String to fully override linkwarden.fullname     | `""`  |

### Linkwarden configuration parameters

| Name                                            | Description                                                                                                                                            | Value        |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------ |
| `linkwarden.replicas`                           | The number of Linkwarden replicas (pods) to deploy                                                                                                     | `1`          |
| `linkwarden.domain`                             | The domain name to assign to Linkwarden, to be re-used as the NextAuth URL and                                                                         | `""`         |
| `linkwarden.nextAuthSecret.value`               | A secret string to encrypt JWTs and hash email verification tokens                                                                                     | `""`         |
| `linkwarden.nextAuthSecret.existingSecret.name` | The name of an existing secret containing the secret string                                                                                            | `""`         |
| `linkwarden.nextAuthSecret.existingSecret.key`  | The key within before mentioned secret containing the actual string                                                                                    | `""`         |
| `linkwarden.paginationTakeCount`                | The number of links to fetch every time you reach the bottom of the web page                                                                           | `20`         |
| `linkwarden.autoscrollTimeout`                  | The amount of time to wait for the web page to be archived (in seconds).                                                                               | `30`         |
| `linkwarden.rearchiveLimit`                     | Adjusts how often a user can trigger a new archive for each link (in minutes).                                                                         | `5`          |
| `linkwarden.maxFileSize`                        | Optionally set a maximum file size                                                                                                                     | `""`         |
| `linkwarden.maxLinksPerUser`                    | Optionally set the maximum amount of links a single user can create                                                                                    | `""`         |
| `linkwarden.archiveTakeCount`                   | Optionally set the number of archives to fetch                                                                                                         | `""`         |
| `linkwarden.browserTimeout`                     | Optionally set timeout duration for the browser                                                                                                        | `""`         |
| `linkwarden.ignoreUnauthorizedCA`               | Optionally ignore unauthorized Certificate Authorities                                                                                                 | `false`      |
| `linkwarden.ignoreHTTPSErrors`                  | Chromium to ignore SSL errors; this is useful to support generation of browser screenshots from sources with self-signed certificates or untrusted CAs | `false`      |
| `linkwarden.data.storageType`                   | The storage type to use for data, can be either 'filesystem' or 's3'                                                                                   | `filesystem` |
| `linkwarden.data.filesystem.dataPath`           | The relative path for data to be stored in                                                                                                             | `data`       |
| `linkwarden.data.filesystem.pvc.size`           | The size given to the PVC for the above data paths                                                                                                     | `5Gi`        |
| `linkwarden.data.filesystem.pvc.storageClass`   | The storageClass given to PVCs                                                                                                                         | `standard`   |
| `linkwarden.data.filesystem.pvc.reclaimPolicy`  | The resourcePolicy given to PVCs                                                                                                                       | `Retain`     |
| `linkwarden.data.filesystem.pvc.existingClaim`  | Provide the name to an existing PVC                                                                                                                    | `""`         |
| `linkwarden.data.s3.bucketName`                 | The name of the S3 bucket to be used for the Linkwarden files                                                                                          | `""`         |
| `linkwarden.data.s3.endpoint`                   | The S3 endpoint to use                                                                                                                                 | `""`         |
| `linkwarden.data.s3.region`                     | The AWS region the S3 bucket is located in                                                                                                             | `""`         |
| `linkwarden.data.s3.forcePathStyle`             | Use path-style bucket addresses instead of AWS' DNS subdomain style                                                                                    | `false`      |
| `linkwarden.data.s3.accessKey`                  | The S3 Access Key, to be used within a Kubernetes secret                                                                                               | `""`         |
| `linkwarden.data.s3.secretKey`                  | The S3 Secret Key, to be used within a Kubernetes secret                                                                                               | `""`         |
| `linkwarden.data.s3.existingSecret`             | The name of an existing Secret with `accessKey` and `secretKey` keys                                                                                   | `""`         |
| `linkwarden.database.user`                      | The user for the PostgreSQL instance - ignored if 'existingSecret' or 'uri' is set                                                                     | `linkwarden` |
| `linkwarden.database.password`                  | The password to the aforementioned user - ignored if 'existingSecret' or 'uri' is set                                                                  | `linkwarden` |
| `linkwarden.database.host`                      | The hostname for the PostgreSQL instance - ignored if 'existingSecret' or 'uri' is set                                                                 | `""`         |
| `linkwarden.database.port`                      | The port for the PostgreSQL instance - ignored if 'existingSecret' or 'uri' is set                                                                     | `5432`       |
| `linkwarden.database.name`                      | The name for the PostgreSQL database - ignored if 'existingSecret' or 'uri' is set                                                                     | `linkwarden` |
| `linkwarden.database.uri`                       | The URI for the PostgreSQL database - ignored if existingSecret is set                                                                                 | `""`         |
| `linkwarden.database.existingSecret`            | The name of the existing secret containing the fully qualified PostgreSQL uri under a `uri` key                                                        | `""`         |
| `linkwarden.auth.disableRegistration`           | Disable registration for Linkwarden                                                                                                                    | `false`      |
| `linkwarden.auth.enableCredentials`             | Enable credential logins for Linkwarden                                                                                                                | `true`       |
| `linkwarden.auth.disableNewSSOUsers`            | Disable new SSO users                                                                                                                                  | `false`      |
| `linkwarden.auth.sso`                           | A list of SSO providers to enable within Linkwarden                                                                                                    | `{}`         |
| `linkwarden.smtp.enabled`                       | Enable email integration within Linkwarden                                                                                                             | `false`      |
| `linkwarden.smtp.fromAddress`                   | The address from which Linkwarden should send emails                                                                                                   | `""`         |
| `linkwarden.smtp.server`                        | The server from which Linkwarden should send emails                                                                                                    | `""`         |

### ConfigMap parameters

| Name                    | Description                             | Value |
| ----------------------- | --------------------------------------- | ----- |
| `configMap.annotations` | Annotations for the ConfigMap resource  | `{}`  |
| `configMap.labels`      | Extra Labels for the ConfigMap resource | `{}`  |

### Common Secret parameters

| Name                 | Description                                                        | Value |
| -------------------- | ------------------------------------------------------------------ | ----- |
| `secret.annotations` | Common annotations for the SMTP, HIBP, Admin and Database secrets  | `{}`  |
| `secret.labels`      | Common extra labels for the SMTP, HIBP, Admin and Database secrets | `{}`  |

### Ingress parameters

| Name                  | Description                                                             | Value   |
| --------------------- | ----------------------------------------------------------------------- | ------- |
| `ingress.enabled`     | Whether to enable Ingress                                               | `false` |
| `ingress.className`   | The IngressClass to use for the pod's ingress                           | `""`    |
| `ingress.whitelist`   | A comma-separated list of IP addresses to whitelist                     | `""`    |
| `ingress.annotations` | Annotations for the Ingress resource                                    | `{}`    |
| `ingress.tls`         | A list of hostnames and secret names to use for TLS                     | `[]`    |
| `ingress.extraHosts`  | A list of extra hosts for the Ingress resource (with linkwarden.domain) | `[]`    |

### Service parameters

| Name                               | Description                                                                             | Value       |
| ---------------------------------- | --------------------------------------------------------------------------------------- | ----------- |
| `service.type`                     | The type of service to create                                                           | `ClusterIP` |
| `service.port`                     | The port to use on the service                                                          | `80`        |
| `service.nodePort`                 | The Node port to use on the service                                                     | `30080`     |
| `service.extraPorts`               | Extra ports to add to the service                                                       | `[]`        |
| `service.annotations`              | Annotations for the service resource                                                    | `{}`        |
| `service.labels`                   | Labels for the service resource                                                         | `{}`        |
| `service.externalTrafficPolicy`    | The external traffic policy for the service                                             | `Cluster`   |
| `service.internalTrafficPolicy`    | The internal traffic policy for the service                                             | `Cluster`   |
| `service.clusterIP`                | Define a static cluster IP for the service                                              | `""`        |
| `service.loadBalancerIP`           | Set the Load Balancer IP                                                                | `""`        |
| `service.loadBalancerClass`        | Define Load Balancer class if service type is `LoadBalancer` (optional, cloud specific) | `""`        |
| `service.loadBalancerSourceRanges` | Service Load Balancer source ranges                                                     | `[]`        |
| `service.externalIPs`              | Service External IPs                                                                    | `[]`        |
| `service.sessionAffinity`          | Session Affinity for Kubernetes service, can be "None" or "ClientIP"                    | `None`      |
| `service.sessionAffinityConfig`    | Additional settings for the sessionAffinity                                             | `{}`        |
| `service.ipFamilyPolicy`           | The ipFamilyPolicy                                                                      | `""`        |

### RBAC parameters

| Name          | Description                      | Value  |
| ------------- | -------------------------------- | ------ |
| `rbac.create` | Whether to create RBAC resources | `true` |
| `rbac.rules`  | Extra rules to add to the Role   | `[]`   |

### Service Account parameters

| Name                         | Description                                                                  | Value   |
| ---------------------------- | ---------------------------------------------------------------------------- | ------- |
| `serviceAccount.create`      | Whether a service account should be created                                  | `true`  |
| `serviceAccount.automount`   | Whether to automount the service account token                               | `false` |
| `serviceAccount.annotations` | Annotations to add to the service account                                    | `{}`    |
| `serviceAccount.name`        | A custom name for the service account, otherwise linkwarden.fullname is used | `""`    |
| `serviceAccount.secrets`     | A list of secrets mountable by this service account                          | `[]`    |

### Liveness Probe parameters

| Name                                | Description                                                 | Value   |
| ----------------------------------- | ----------------------------------------------------------- | ------- |
| `livenessProbe.enabled`             | Enable or disable the use of liveness probes                | `false` |
| `livenessProbe.initialDelaySeconds` | Configure the initial delay seconds for the liveness probe  | `5`     |
| `livenessProbe.timeoutSeconds`      | Configure the initial delay seconds for the liveness probe  | `1`     |
| `livenessProbe.periodSeconds`       | Configure the seconds for each period of the liveness probe | `10`    |
| `livenessProbe.successThreshold`    | Configure the success threshold for the liveness probe      | `1`     |
| `livenessProbe.failureThreshold`    | Configure the failure threshold for the liveness probe      | `10`    |

### Readiness Probe parameters

| Name                                 | Description                                                  | Value   |
| ------------------------------------ | ------------------------------------------------------------ | ------- |
| `readinessProbe.enabled`             | Enable or disable the use of readiness probes                | `false` |
| `readinessProbe.initialDelaySeconds` | Configure the initial delay seconds for the readiness probe  | `5`     |
| `readinessProbe.timeoutSeconds`      | Configure the initial delay seconds for the readiness probe  | `1`     |
| `readinessProbe.periodSeconds`       | Configure the seconds for each period of the readiness probe | `10`    |
| `readinessProbe.successThreshold`    | Configure the success threshold for the readiness probe      | `1`     |
| `readinessProbe.failureThreshold`    | Configure the failure threshold for the readiness probe      | `3`     |

### Startup Probe parameters

| Name                               | Description                                                | Value   |
| ---------------------------------- | ---------------------------------------------------------- | ------- |
| `startupProbe.enabled`             | Enable or disable the use of readiness probes              | `false` |
| `startupProbe.initialDelaySeconds` | Configure the initial delay seconds for the startup probe  | `5`     |
| `startupProbe.timeoutSeconds`      | Configure the initial delay seconds for the startup probe  | `1`     |
| `startupProbe.periodSeconds`       | Configure the seconds for each period of the startup probe | `10`    |
| `startupProbe.successThreshold`    | Configure the success threshold for the startup probe      | `1`     |
| `startupProbe.failureThreshold`    | Configure the failure threshold for the startup probe      | `10`    |

### PodDisruptionBudget parameters

| Name                               | Description                                           | Value  |
| ---------------------------------- | ----------------------------------------------------- | ------ |
| `podDisruptionBudget.enabled`      | Enable the pod disruption budget                      | `true` |
| `podDisruptionBudget.minAvailable` | The minimum amount of pods which need to be available | `1`    |

### Pod settings

| Name                | Description                                          | Value |
| ------------------- | ---------------------------------------------------- | ----- |
| `resources`         | The resource limits/requests for the Linkwarden pod  | `{}`  |
| `volumes`           | Define volumes for the Linkwarden pod                | `[]`  |
| `volumeMounts`      | Define volumeMounts for the Linkwarden pod           | `[]`  |
| `initContainers`    | Define initContainers for the main Linkwarden server | `[]`  |
| `nodeSelector`      | Node labels for pod assignment                       | `{}`  |
| `tolerations`       | Tolerations for pod assignment                       | `[]`  |
| `affinity`          | Affinity for pod assignment                          | `{}`  |
| `strategy`          | Specify a deployment strategy for the Linkwarden pod | `{}`  |
| `podAnnotations`    | Extra annotations for the Linkwarden pod             | `{}`  |
| `podLabels`         | Extra labels for the Linkwarden pod                  | `{}`  |
| `priorityClassName` | The name of an existing PriorityClass                | `""`  |

### Security context settings

| Name                 | Description                                      | Value |
| -------------------- | ------------------------------------------------ | ----- |
| `podSecurityContext` | Security context settings for the Linkwarden pod | `{}`  |
| `securityContext`    | General security context settings for            | `{}`  |

### Bitnami&reg; PostgreSQL parameters

| Name                                 | Description                                                                                            | Value        |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------ | ------------ |
| `postgresql.enabled`                 | Enable or disable the PostgreSQL subchart                                                              | `true`       |
| `postgresql.auth.enablePostgresUser` | Assign a password to the "postgres" admin user. Otherwise, remote access will be blocked for this user | `true`       |
| `postgresql.auth.postgresPassword`   | Password for the "postgres" admin user. Ignored if `auth.existingSecret` is provided                   | `postgres`   |
| `postgresql.auth.username`           | Name for a custom user to create                                                                       | `linkwarden` |
| `postgresql.auth.password`           | Password for the custom user to create. Ignored if `auth.existingSecret` is provided                   | `linkwarden` |
| `postgresql.auth.database`           | Name for a custom database to create                                                                   | `linkwarden` |
| `postgresql.auth.usePasswordFiles`   | Mount credentials as a files instead of using an environment variable                                  | `false`      |

### PostgreSQL Primary parameters

| Name                                           | Description                                                    | Value               |
| ---------------------------------------------- | -------------------------------------------------------------- | ------------------- |
| `postgresql.primary.name`                      | Name of the primary database (eg primary, master, leader, ...) | `primary`           |
| `postgresql.primary.persistence.enabled`       | Enable PostgreSQL Primary data persistence using PVC           | `true`              |
| `postgresql.primary.persistence.existingClaim` | Name of an existing PVC to use                                 | `""`                |
| `postgresql.primary.persistence.storageClass`  | PVC Storage Class for PostgreSQL Primary data volume           | `""`                |
| `postgresql.primary.persistence.accessModes`   | PVC Access Mode for PostgreSQL volume                          | `["ReadWriteOnce"]` |
| `postgresql.primary.persistence.size`          | PVC Storage Request for PostgreSQL volume                      | `5Gi`               |
