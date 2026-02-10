# matrix-slack-bridge - Deployment Summary

## 2026-02-10 Deployment Status

### Completed Infrastructure
All Kubernetes resources deployed successfully via Flux:

1. **Secrets** (namespace: apps)
   - `mautrix-slack-config` - Bridge configuration
   - `mautrix-slack-registration` - Appservice registration for Synapse
   - `mautrix_slack_as_token` / `mautrix_slack_hs_token` - SOPS encrypted in secrets/k8s-secrets.enc.yaml

2. **Deployment** - mautrix-slack
   - Image: dock.mau.dev/mautrix/slack:latest
   - Port: 29333
   - Status: 0/1 ready (CrashLoopBackOff)

3. **Service** - mautrix-slack (ClusterIP: 10.43.90.227:29333)

4. **PVC** - mautrix-slack (1Gi, rook-ceph-block, Bound)

5. **Synapse Integration**
   - Registration file mounted at: /synapse/config/conf.d/mautrix-slack-registration.yaml
   - Appservice config included in Synapse app_service_config_files

### Current Issue: Config Format Error

The bridge is failing with:
```
Legacy bridge config detected, but hacky network config migrator is not set
```

**Root Cause**: mautrix-slack v0.1.0+ uses bridgev2 format which may differ from the config structure used by mautrix-discord, despite both being Go-based bridges.

**Attempts Made**:
1. Removed `slack:` and `backfill:` sections from config
2. Added `"*": "relay"` permission like Discord
3. Used `latest` image tag instead of specific version

**Config Structure** (current):
```yaml
homeserver:
  address: http://synapse-matrix-synapse.apps.svc.cluster.local:8008
  domain: josevictor.me
appservice:
  id: slack
  address: http://mautrix-slack.apps.svc.cluster.local:29333
  port: 29333
  database:  # nested under appservice (like Discord)
    type: postgres
    uri: postgresql://...
bridge:
  permissions:
    "@jose:josevictor.me": admin
    "*": relay
  encryption:
    allow: false
```

### Next Steps to Resolve

1. **Generate proper bridgev2 config**:
   ```bash
   kubectl run -n apps --rm -i --restart=Never generate-config \
     --image=dock.mau.dev/mautrix/slack:latest -- \
     /usr/bin/mautrix-slack -e > /tmp/slack-config.yaml
   ```

2. **Compare generated config** with current and identify structural differences

3. **Update matrix-config.enc.nix** with correct bridgev2 format

4. **Alternative**: Try specific older image version that accepts legacy config format

### Manual Login (Post-Config-Fix)

Once config issue is resolved:

1. Start chat with `@slackbot:josevictor.me`
2. Send: `login token <xoxc-token> <xoxd-cookie>`
3. Token source: Slack web app localStorage
4. Cookie: browser cookie named `d`

### Rollback

To disable bridge:
```bash
git mv modules/kubenix/apps/mautrix-slack.nix modules/kubenix/apps/_mautrix-slack.nix
make manifests && git commit -am "Disable mautrix-slack" && git push
```
