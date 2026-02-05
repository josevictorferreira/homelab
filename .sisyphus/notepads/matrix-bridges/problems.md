# Matrix Bridges - Problems

## Unresolved Blockers

### Secrets Not Populated
- secrets/k8s-secrets.enc.yaml contains placeholder values (TODO-INSERT-VALUE) that need to be replaced with real values
- Run `make secrets` to populate: synapse_macaroon_secret_key, synapse_form_secret, synapse_signing_key, synapse_admin_username, synapse_admin_password, mautrix_*_tokens, slack_*_tokens, discord_bot_token

## External Dependencies Awaiting User Input
- Slack app token and bot token (xapp-..., xoxb-...)
- Discord bot token
- User needs to scan WhatsApp QR code after deployment
