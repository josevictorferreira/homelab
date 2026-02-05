# Issues and Gotchas

## [2026-02-05] Initialization
- No issues yet

## [2026-02-05] openclaw-config.enc.nix not rendered
- **Root cause**: file was untracked (`?? modules/kubenix/apps/openclaw-config.enc.nix`). Flake eval uses git tree, so untracked files are invisible; kubenix renderer discovery (`builtins.readDir`) never saw it.
- **Fix**: `git add modules/kubenix/apps/openclaw-config.enc.nix && nix build .#gen-manifests -L`; now generates both `openclaw-config.enc.yaml` + `openclaw.yaml`.
- **Lesson**: ANY new `modules/kubenix/**/*.nix` file MUST be `git add`-ed before `make manifests` / `nix build`, or it won't render.

## [2026-02-05] Secret key not injected by vals/SOPS
- **Root cause**: `openclaw_gateway_token` key was missing from `secrets/k8s-secrets.enc.yaml` (subagent claimed success but verification proved otherwise).
- **Fix**: Manual decrypt → insert line → re-encrypt with SOPS.
- **Lesson**: ALWAYS verify secrets exist before running manifest pipeline: `sops -d secrets/k8s-secrets.enc.yaml | grep <key>`.
