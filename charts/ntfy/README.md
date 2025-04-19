# FMJ Studios - ntfy Helm Chart <img src="https://raw.githubusercontent.com/binwiederhier/ntfy/9d3fc20e583564e40af5afb90233f4714fdfcb4c/web/public/static/images/pwa-512x512.png" alt="ntfy Logo" width="175" height="175" align="right" loading="lazy">

ntfy (pronounced notify) is a simple HTTP-based pub-sub notification service. It allows you to send notifications to
your phone or desktop via scripts from any computer, and/or using a REST API. It's infinitely flexible, and 100% free
software.
It delivers all of these features within a single Docker image available
on [Docker Hub](https://hub.docker.com/r/binwiederhier/ntfy).

> Head to the [ntfy GitHub Repository](https://github.com/binwiederhier/ntfy) or
> their [Website](https://ntfy.sh/) for in-depth [documentation](https://docs.ntfy.sh/)
> and [configuration guides](https://docs.ntfy.sh/config/).

## ✨ TL;DR

### Helm Repository Installation

```shell
helm repo add fmjstudios https://fmjstudios.github.io/helm
helm install ntfy fmjstudios/ntfy --version X.Y.Z
```

### OCI Installation

```shell
helm install oci://ghcr.io/fmjstudios/helm/ntfy:X.Y.Z
```

## Introduction

This chart bootstraps a
ntfy [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
or [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) on
a [Kubernetes](https://kubernetes.io) cluster using the [Helm](https://helm.sh/) package manager. For cluster networking
a [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
and [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) manifest is also created, whereas the
Ingress needs to be explicitly enabled. Lastly the chart configures
a [PodDisruptionBudget](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) if
enabled. [RBAC manifests](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) are enabled by default.

The chart supports the configuration of
all [ntfy environment variables](https://docs.ntfy.sh/config/) via the `ntfy` key in
Helm's _values_ and makes use of the official Docker Hub container image, although this is configurable via the Image
Parameters.

## Parameters

### ntfy Image parameters

| Name                | Description                                                         | Value                |
| ------------------- | ------------------------------------------------------------------- | -------------------- |
| `image.registry`    | The Docker registry to pull the image from                          | `docker.io`          |
| `image.repository`  | The registry repository to pull the image from                      | `binwiederhier/ntfy` |
| `image.tag`         | The image tag to pull                                               | `v2.11.0`            |
| `image.digest`      | The image digest to pull                                            | `""`                 |
| `image.pullPolicy`  | The Kubernetes image pull policy                                    | `IfNotPresent`       |
| `image.pullSecrets` | A list of secrets to use for pulling images from private registries | `[]`                 |

### Name overrides

| Name               | Description                                | Value |
| ------------------ | ------------------------------------------ | ----- |
| `nameOverride`     | String to partially override ntfy.fullname | `""`  |
| `fullnameOverride` | String to fully override ntfy.fullname     | `""`  |

### Workload overrides

| Name   | Description                                                            | Value         |
| ------ | ---------------------------------------------------------------------- | ------------- |
| `kind` | The kind of workload to deploy ntfy as (`StatefulSet` or `Deployment`) | `StatefulSet` |

### ntfy Configuration parameters

| Name                                         | Description                                                                                            | Value           |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------ | --------------- |
| `ntfy.baseURL`                               | The public facing URL for the service (e.g. https://ntfy.example.com)                                  | `""`            |
| `ntfy.listenHTTP`                            | The listen address for the HTTP server (e.g. ":80", "127.0.0.1:80")                                    | `""`            |
| `ntfy.listenHTTPS`                           | The listen address for the HTTPS server (e.g. ":443", "127.0.0.1:443") -                               | `""`            |
| `ntfy.listenUnix`                            | The path to a Unix socket to listen on (e.g. "/var/run/ntfy/ntfy.sock")                                | `""`            |
| `ntfy.listenUnixMode`                        | The Linux permissions for the Unix socket (e.g. "0700")                                                | `""`            |
| `ntfy.keyFile`                               | The path to a certificate key file (e.g. "/var/lib/ntfy/tls.key")                                      | `""`            |
| `ntfy.certFile`                              | The path to a certificate file (e.g. "/var/lib/ntfy/tls.crt")                                          | `""`            |
| `ntfy.firebaseKeyFile`                       | The path to a Firebase key file (e.g. "/var/lib/ntfy/key.json")                                        | `""`            |
| `ntfy.behindProxy`                           | Whether or not ntfy is hosted behind a proxy                                                           | `false`         |
| `ntfy.keepaliveInterval`                     | Interval in which keepalive messages are sent to the client                                            | `""`            |
| `ntfy.managerInterval`                       | Interval in which the manager prunes old messages                                                      | `""`            |
| `ntfy.disallowedTopics`                      | Define topic names that are not allowed                                                                | `[]`            |
| `ntfy.webRoot`                               | Define topic names that are not allowed                                                                | `""`            |
| `ntfy.enableSignup`                          | Allow users to sign up via the web app or API                                                          | `false`         |
| `ntfy.enableLogin`                           | Allow users to sign in via the web app or API                                                          | `false`         |
| `ntfy.enableReservations`                    | Allow users to reserve topics                                                                          | `false`         |
| `ntfy.globalTopicLimit`                      | The total number of topics before the server rejects new topics                                        | `15000`         |
| `ntfy.data.rootPath`                         | The root path for ntfy to store its' files                                                             | `/var/lib/ntfy` |
| `ntfy.data.pvc.size`                         | The size given to the new PVC                                                                          | `5Gi`           |
| `ntfy.data.pvc.storageClass`                 | The storageClass given to the new PVC                                                                  | `standard`      |
| `ntfy.data.pvc.reclaimPolicy`                | The resourcePolicy given to the new PVC                                                                | `Retain`        |
| `ntfy.data.pvc.existingClaim`                | Provide the name to an existing PVC                                                                    | `""`            |
| `ntfy.cache.file`                            | The path where to create the SQLite cache database, beginning at ntfy.data.rootPath (e.g. "cache.db")  | `cache.db`      |
| `ntfy.cache.duration`                        | The duration for which messages will be buffered before they are deleted (e.g. "12h")                  | `""`            |
| `ntfy.cache.startupQueries`                  | SQLite queries to run on database initialization (e.g. to enable WAL mode)                             | `""`            |
| `ntfy.cache.batchSize`                       | The amount of messages within a single batch (e.g. 32)                                                 | `0`             |
| `ntfy.cache.batchTimeout`                    | The timeout after which to write the batched messages to the DB (e.g. "0ms")                           | `""`            |
| `ntfy.auth.file`                             | The path where to create the SQLite user database (e.g. "auth.db")                                     | `""`            |
| `ntfy.auth.defaultAccess`                    | The default access level for new users. Can be `deny-all`, `read-only` or `write-only`.                | `""`            |
| `ntfy.auth.startupQueries`                   | SQLite queries to run on database initialization (e.g. to enable WAL mode)                             | `""`            |
| `ntfy.attachment.cacheDir`                   | The directory for attached files (e.g. "attachments")                                                  | `""`            |
| `ntfy.attachment.totalSizeLimit`             | The maximum total size of cacheDir (e.g. "5G")                                                         | `""`            |
| `ntfy.attachment.fileSizeLimit`              | The maximum size of a single attachment (e.g. "15M")                                                   | `""`            |
| `ntfy.attachment.expiryDuration`             | The duration after which uploaded attachments are deleted (e.g. "3h")                                  | `""`            |
| `ntfy.smtp.senderAddr`                       | The hostname:port of the SMTP server (e.g. "mail.example.com:587")                                     | `""`            |
| `ntfy.smtp.senderFrom`                       | The e-=mail address of the sender (e.g. "ntfy@example.com")                                            | `""`            |
| `ntfy.smtp.senderUser`                       | The username of the SMTP user (e.g. "ntfy@example.com")                                                | `""`            |
| `ntfy.smtp.senderPass`                       | The password of the SMTP user (e.g. "ntfy@example.com")                                                | `""`            |
| `ntfy.smtp.existingSecret`                   | An existing secret with a `username` and `password` key                                                | `""`            |
| `ntfy.smtp.incoming.listen`                  | The IP address and port the SMTP server will listen on (e.g. ":25" or "0.0.0.0:25")                    | `""`            |
| `ntfy.smtp.incoming.domain`                  | The email domain (e.g. "example.com")                                                                  | `""`            |
| `ntfy.smtp.incoming.addrPrefix`              | Optional prefix to prevent spam. If set to "ntfy-" for example,                                        | `""`            |
| `ntfy.web.publicKey`                         | is the generated VAPID public key, (e.g. "AA...")                                                      | `""`            |
| `ntfy.web.privateKey`                        | is the generated VAPID private key, (e.g. "AA...")                                                     | `""`            |
| `ntfy.web.existingSecret`                    | An existing secret with a `privateKey` and `publicKey` a                                               | `""`            |
| `ntfy.web.file`                              | is a database file to keep track of browser subscription endpoints (e.g. "/var/cache/ntfy/webpush.db") | `""`            |
| `ntfy.web.emailAddress`                      | is the admin email address send to the push provider, (e.g. "sysadmin@example.com")                    | `""`            |
| `ntfy.web.startupQueries`                    | SQLite queries to run on database initialization (e.g. to enable WAL mode)                             | `""`            |
| `ntfy.twilio.accountSID`                     | is the Twilio account SID, (e.g. "AC12345beefbeef67890beefbeef122586")                                 | `""`            |
| `ntfy.twilio.token`                          | is the Twilio authentication token, (e.g. "ThisIsAnAuthenticationToken")                               | `""`            |
| `ntfy.twilio.existingSecret`                 | An existing secret containing a `accountSID` and `token` key                                           | `""`            |
| `ntfy.twilio.phoneNumber`                    | The outgoing Twilio phone number (e.g. "+18775132586")                                                 | `""`            |
| `ntfy.twilio.verifyService`                  | Twilio verify service SID (e.g. "VA12345beefbeef67890beefbeef122586")                                  | `""`            |
| `ntfy.upstream.baseURL`                      | The base URL of the upstream server, should be "https://ntfy.sh"                                       | `""`            |
| `ntfy.upstream.accessToken`                  | the token used to authenticate with the upstream APNS server                                           | `""`            |
| `ntfy.upstream.existingSecret`               | A existing Secret containing a `token` key                                                             | `""`            |
| `ntfy.message.sizeLimit`                     | The maximum size of a message body (e.g. "4k")                                                         | `""`            |
| `ntfy.message.delayLimit`                    | The maximum delay of a message when using the "Delay" header (e.g. "12h")                              | `""`            |
| `ntfy.visitor.subscriptionLimit`             | The number of subscriptions per visitor (IP address)                                                   | `30`            |
| `ntfy.visitor.requestLimitBurst`             | The initial bucket of requests each visitor has (e.g. "60")                                            | `60`            |
| `ntfy.visitor.requestLimitReplenish`         | The rate at which the bucket is refilled (e.g. "5s")                                                   | `5s`            |
| `ntfy.visitor.requestLimitExemptHosts`       | A comma-separated list of hostnames, IPs or CIDRs to be                                                | `""`            |
| `ntfy.visitor.messageDailyLimit`             | Hard daily limit of messages per visitor and day. The limit is reset                                   | `15000`         |
| `ntfy.visitor.emailLimitBurst`               | The initial bucket of emails each visitor has (e.g. "60")                                              | `16`            |
| `ntfy.visitor.emailLimitReplenish`           | The rate at which the bucket is refilled (e.g. "5s")                                                   | `1h`            |
| `ntfy.visitor.attachmentTotalSizeLimit`      | The total storage limit used for attachments per visitor                                               | `100M`          |
| `ntfy.visitor.attachmentDailyBandwidthLimit` | The total daily attachment download/upload traffic limit per visitor                                   | `500M`          |
| `ntfy.visitor.subscriberRateLimiting`        | Whether to enable subscriber-based rate limiting                                                       | `false`         |
| `ntfy.stripe.secretKey`                      | The key used for the Stripe API communication                                                          | `""`            |
| `ntfy.stripe.webhookKey`                     | The webhook key used for the Stripe API communication                                                  | `""`            |
| `ntfy.stripe.existingSecret`                 | An existing secret containing a `secretKey` and `weboohKey` keys                                       | `""`            |
| `ntfy.stripe.billingContact`                 | is an email address or site displayed in the "Upgrade tier" dialog to let people reach                 | `""`            |
| `ntfy.metrics.enabled`                       | enables the /metrics endpoint for the ntfy server                                                      | `false`         |
| `ntfy.metrics.listenHTTP`                    | exposes the metrics endpoint via a dedicated [IP]:port. If set, this option                            | `""`            |
| `ntfy.metrics.profileListenHTTP`             | If enabled, ntfy will listen on a dedicated listen IP/port                                             | `""`            |
| `ntfy.log.level`                             | One of "trace", "debug", "info" (default), "warn" or "error"                                           | `info`          |
| `ntfy.log.levelOverrides`                    | lets you override the log level if certain fields match                                                | `""`            |
| `ntfy.log.format`                            | One of "text" (default) or "json"                                                                      | `text`          |
| `ntfy.log.file`                              | The filename to write logs to. If this is not set, ntfy logs to stderr                                 | `""`            |

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

| Name                  | Description                                                        | Value   |
| --------------------- | ------------------------------------------------------------------ | ------- |
| `ingress.enabled`     | Whether to enable Ingress                                          | `false` |
| `ingress.className`   | The IngressClass to use for the pod's ingress                      | `""`    |
| `ingress.whitelist`   | A comma-separated list of IP addresses to whitelist                | `""`    |
| `ingress.annotations` | Annotations for the Ingress resource                               | `{}`    |
| `ingress.tls`         | A list of hostnames and secret names to use for TLS                | `[]`    |
| `ingress.extraHosts`  | A list of extra hosts for the Ingress resource (with ntfy.baseURL) | `[]`    |

### Service parameters

| Name                               | Description                                                                             | Value       |
| ---------------------------------- | --------------------------------------------------------------------------------------- | ----------- |
| `service.type`                     | The type of service to create                                                           | `ClusterIP` |
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
| `service.ipFamilyPolicy`           | The ipFamilyPolicy                                                                      | `{}`        |
| `service.ports.http`               | The port to use on the service for HTTP traffic                                         | `8080`      |
| `service.ports.https`              | The port to use on the service for HTTPS traffic in case ntfy.listenHTTPS is active.    | `8443`      |

### RBAC parameters

| Name          | Description                      | Value  |
| ------------- | -------------------------------- | ------ |
| `rbac.create` | Whether to create RBAC resources | `true` |
| `rbac.rules`  | Extra rules to add to the Role   | `[]`   |

### Service Account parameters

| Name                         | Description                                                            | Value   |
| ---------------------------- | ---------------------------------------------------------------------- | ------- |
| `serviceAccount.create`      | Whether a service account should be created                            | `true`  |
| `serviceAccount.automount`   | Whether to automount the service account token                         | `false` |
| `serviceAccount.annotations` | Annotations to add to the service account                              | `{}`    |
| `serviceAccount.name`        | A custom name for the service account, otherwise ntfy.fullname is used | `""`    |
| `serviceAccount.secrets`     | A list of secrets mountable by this service account                    | `[]`    |

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

| Name                | Description                                    | Value |
| ------------------- | ---------------------------------------------- | ----- |
| `resources`         | The resource limits/requests for the ntfy pod  | `{}`  |
| `volumes`           | Define volumes for the ntfy pod                | `[]`  |
| `volumeMounts`      | Define volumeMounts for the ntfy pod           | `[]`  |
| `initContainers`    | Define initContainers for the main ntfy server | `[]`  |
| `nodeSelector`      | Node labels for pod assignment                 | `{}`  |
| `tolerations`       | Tolerations for pod assignment                 | `[]`  |
| `affinity`          | Affinity for pod assignment                    | `{}`  |
| `strategy`          | Specify a deployment strategy for the ntfy pod | `{}`  |
| `podAnnotations`    | Extra annotations for the ntfy pod             | `{}`  |
| `podLabels`         | Extra labels for the ntfy pod                  | `{}`  |
| `priorityClassName` | The name of an existing PriorityClass          | `""`  |

### Security context settings

| Name                 | Description                                | Value |
| -------------------- | ------------------------------------------ | ----- |
| `podSecurityContext` | Security context settings for the ntfy pod | `{}`  |
| `securityContext`    | General security context settings for      | `{}`  |
