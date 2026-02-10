# matrix-slack-bridge - Manual Login Runbook

## Prerequisites
- Bridge config issue resolved (pod running)
- Access to company Slack workspace via web browser
- Matrix client connected to josevictor.me homeserver

## Step 1: Get Slack Credentials

1. Open Slack web app in browser
2. Open browser DevTools (F12) → Console or Application tab
3. Get token:
   ```javascript
   JSON.parse(localStorage.localConfig_v2).teams[Object.keys(JSON.parse(localStorage.localConfig_v2).teams)[0]].token
   ```
4. Get cookie:
   - Go to Application/Storage → Cookies
   - Find cookie named `d` (domain: `.slack.com`)
   - Copy value (starts with `xoxd-`)

## Step 2: Login via Matrix

1. Start Direct Message with `@slackbot:josevictor.me`
2. Send: `login token <xoxc-token> <xoxd-cookie>`
   - Replace `<xoxc-token>` with token from step 1 (starts with `xoxc-`)
   - Replace `<xoxd-cookie>` with cookie from step 1 (starts with `xoxd-`)
3. Wait for confirmation message

## Step 3: Verify Bridge

1. Send: `help` to see available commands
2. Send: `list` to see connected workspaces
3. Bridge should auto-create portal rooms for recent conversations

## Security Note

- Token+cookie grants full Slack workspace access
- Matrix DM with bot is NOT encrypted (E2EE disabled for this bridge)
- Consider redacting the login message after successful connection

## Troubleshooting

**Bridge not responding**: Check if pod is running
```bash
kubectl get pods -n apps -l app=mautrix-slack
```

**Login fails**: Token/cookie may be expired. Repeat credential extraction.

**No portals created**: Check bridge logs
```bash
kubectl logs -n apps -l app=mautrix-slack
```
