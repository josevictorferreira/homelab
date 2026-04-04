## 2026-04-03T17:40:00Z Task: init
Notepad initialized for lossless-claw-openclaw-memory.

## 2026-04-03T18:15:00Z Implement lossless-claw deps
- Created lossless-claw-deps.nix and package-lock.json
- Pinned @mariozechner/pi-agent-core 0.64.0, @mariozechner/pi-ai 0.64.0, @sinclair/typebox 0.34.48
- Used buildNpmPackage pattern from matrix-deps.nix

## 2026-04-03T20:10:00Z Bundle lossless-claw into openclaw-nix image
- Added losslessClawPackage import from lossless-claw-deps.nix
- Added losslessClawSource fetchurl for GitHub tarball (v0.5.3)
- Correct hash: sha256-3WzvaGPRBbHoR5hqJyk6b70CPfvWKzaaaQCjrWXZQNg=
- Added tarball extraction script in openclawRootfs before plugin loop
- Added node_modules copy from losslessClawPackage to lossless-claw extension
- Build exits 0 - verification passes
- ISSUE: tar extraction fails with "Permission denied" in nix build environment
  - tar: tui: Cannot mkdir: Permission denied
  - tar: test: Cannot mkdir: Permission denied
  - Same for other directories in tarball
- Root cause: The extensions/ directory from gateway copy has permission restrictions
- Workaround needed: extraction may require different approach (fetch as derivation first)

## 2026-04-03T20:25:00Z Task2 Fix: Correct extraction and node_modules placement
- Issue: prior extraction tried to mkdir in read-only extensions/ dir
- Fix: chmod -R u+w on extensions/ before writing
- Use temp dir for tarball extraction: /tmp/lossless-extract
- Copy only needed files (openclaw.plugin.json, package.json, src/) to extensions/lossless-claw/
- Plugin loop then copies to dist/extensions/lossless-claw/
- node_modules must be copied to dist/extensions/lossless-claw/node_modules
- Verified: podman shows all required files in dist/extensions/lossless-claw/
- Dynamic CephFS configuration patching using jq in the deployment startup command allows applying stateful overrides safely without requiring custom Docker builds.

## 2026-04-04T00:00:00Z Fix: lossless-claw index.ts missing
- lossless-claw openclaw.plugin.json entry is ./index.ts; runtime expects it under /lib/openclaw/dist/extensions/lossless-claw/index.ts.
- Fix: copy index.ts from extracted lossless-claw-0.5.3/ into extensions/lossless-claw, then explicitly copy into dist/extensions/lossless-claw (plugin loop intentionally avoids top-level .ts).
