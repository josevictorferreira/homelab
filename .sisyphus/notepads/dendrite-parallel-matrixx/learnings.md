Created matrixx.nix deployment module for Dendrite with secret mount, media PVC, service, and ingress.

## Dendrite Signing Key Fix (2026-03-20)

### Key Generation
- Use: `podman run --rm --entrypoint generate-keys -v /tmp/keyout:/tmp/keyout ghcr.io/element-hq/dendrite-monolith:v0.15.2 --private-key /tmp/keyout/matrix_key.pem`
- Output format: `-----BEGIN MATRIX PRIVATE KEY-----` PEM format
- Add to SOPS via `sops --set '["dendrite_signing_key"] "<value>"'`

### Secret Structure
- `matrixx-config` secret contains BOTH `dendrite.yaml` AND `matrix_key.pem` keys
- `dendrite.yaml` has `global.private_key: /var/lib/dendrite/matrix_key.pem`
- `matrix_key.pem` contains the PEM key content (from `kubenix.lib.secretsFor "dendrite_signing_key"`)

### Volume Mount Pattern for Secret Key File
- Volume `key` uses secret `matrixx-config` with `items: [{key: matrix_key.pem, path: matrix_key.pem}]`
- Mounted at `/var/lib/dendrite` (directory) — key appears at `/var/lib/dendrite/matrix_key.pem`
- The `private_key` config path must match exactly: `/var/lib/dendrite/matrix_key.pem`

### Stray volumes Block Fix
- The stray `volumes = [...]` in the job spec (lines 140-147) was valid Nix but poorly indented
- Fixed by rewriting with proper indentation inside `spec.template.spec`
