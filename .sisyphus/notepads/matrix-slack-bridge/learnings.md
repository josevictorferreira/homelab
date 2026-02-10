# matrix-slack-bridge - learnings

## 2026-02-10
- mautrix-slack secrets live in `modules/kubenix/apps/matrix-config.enc.nix` as 2 K8s Secrets:
  - `mautrix-slack-registration`: `stringData.registration.yaml` via `kubenix.lib.toYamlStr` (id=slack, url svc:29333, as/hs tokens via `secretsInlineFor`, user namespace regex for `@slackbot` + `@slack_.*`).
  - `mautrix-slack-config`: `stringData.config.yaml` via `kubenix.lib.toYamlStr`.
- Slack bridge config follows mautrix-discord schema: Postgres config is **nested under** `appservice.database` (not top-level `database`).
- Lock down permissions: no wildcard; only `@jose:josevictor.me = admin`.
- Encryption disabled: `bridge.encryption.allow = false`.
- Backfill “from now on”: `backfill.enabled = true; backfill.max_initial_messages = 0;` and `slack.backfill.conversation_count = -1`.
