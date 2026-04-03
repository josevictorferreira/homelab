## 2026-04-03T17:40:00Z Task: init
Decision log initialized.

## 2026-04-03T18:15:00Z Decision
- Implement lossless-claw deps as pinned Nix FOD
- Use exact versions 0.64.0 for pi-agent-core and pi-ai, 0.34.48 for typebox
- Keep placeholder npmDepsHash to be resolved later

## 2026-04-03T20:15:00Z Decision: Image wiring approach
- Use losslessClawPackage from lossless-claw-deps.nix for node_modules
- Fetch lossless-claw source via pkgs.fetchurl from GitHub tags
- Tarball URL: https://github.com/Martian-Engineering/lossless-claw/archive/refs/tags/v0.5.3.tar.gz
- Extract tarball before plugin processing loop, then copy node_modules
- Issue: tar extraction fails in nix build due to permissions on extensions/ directory
- Alternative approaches considered:
  1. Fetch tarball as separate derivation (complex)
  2. Use npm package @martian-engineering/lossless-claw (not on npm registry)
  3. Fetch source from git repo directly (would need additional tooling)
