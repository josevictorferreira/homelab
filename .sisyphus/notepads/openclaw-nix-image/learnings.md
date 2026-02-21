# OpenClaw Nix Image - Learnings

## 2026-02-21 Initial Analysis

### Current kubenix/openclaw.nix Behavior
- Image: `ghcr.io/openclaw/openclaw:2026.2.19@sha256:5352d3ababbc12237fda60fe00a25237441eb7bb5e3d3062a6b0b5fbd938734d`
- Runtime tool installs (to be baked into image):
  - apt-get: curl, xz-utils, jq, git, python3-pip
  - curl download: ffmpeg (johnvansickle.com)
  - curl installer: uv (astral.sh)
  - npm install: @google/gemini-cli
  - curl download: gh (github.com/cli/cli)
  - pip3 install: requests

### Config Path & Structure
- Config: `/home/node/.openclaw/openclaw.json`
- Workspace: `/home/node/.openclaw/workspace`
- PATH: `/home/node/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`

### Env Var Substitution (allowlist)
From current implementation (lines 76-79):
- `OPENCLAW_MATRIX_TOKEN`
- `ELEVENLABS_API_KEY`
- `MOONSHOT_API_KEY`
- `OPENROUTER_API_KEY`
- `WHATSAPP_NUMBER`
- `WHATSAPP_BOT_NUMBER`

### Known Bug (to fix)
Line 254 in openclaw.nix:
```nix
OPENROUTER_API_KEY = "\${OPENCLAW_MATRIX_TOKEN}";  # WRONG!
```
Should use `OPENROUTER_API_KEY` placeholder, not matrix token.

### Matrix Extension npm Install
- Location: `/app/extensions/matrix`
- Strips workspace: protocol deps (node can't handle)
- Runs: `npm install --omit=dev --no-package-lock --legacy-peer-deps`

### Existing Image Patterns (images/)
- `openclaw-matrix.nix`: Uses `pullImage` + `buildImage` overlay
- `mcpo.nix`: Pure Nix build with `buildImage`, embeds config
- Common: `copyToRoot`, `extraCommands` for tmp dirs, `config.Env`

## Volume Contract (from plan)
- `/config`: Ephemeral, seeded from template each start
- `/state`: Persistent (workspace, creds, skills, tool installs/caches)
- `/logs`: Persistent logs

## 2026-02-21 Entrypoint Script Implementation

### Shell Variable Indirection Pattern
For POSIX-compliant variable indirection (getting value of var named in another var):
```sh
var_value=$(eval printf '%s' "\$$var_name")
```
This works across all POSIX shells unlike bash's `${!var_name}`.

### Sed Pattern Escaping for ${VAR}
To match literal `${VAR}` in sed:
```sh
sed "s|\\\${VAR_NAME}|replacement|g"
```
- Shell processes `\\\${` → `\${`
- Sed interprets `\${` as literal `${`

### Security: Allowlist Pattern
Critical to only substitute known env vars:
```sh
ALLOWLIST="OPENCLAW_MATRIX_TOKEN ELEVENLABS_API_KEY MOONSHOT_API_KEY OPENROUTER_API_KEY WHATSAPP_NUMBER WHATSAPP_BOT_NUMBER"
for var_name in ${ALLOWLIST}; do
    # only substitute these
```
Prevents accidental exposure of arbitrary env vars like `PATH`, `HOME`, etc.

### POSIX Compatibility Notes
- Use `#!/bin/sh` not `#!/bin/bash`
- Use `$(cmd)` not backticks
- Avoid bash arrays, use space-separated strings
- `sed -i` is widely supported (not pure POSIX but works in busybox/alpine)

### Testing Pattern
Always test entrypoint scripts with actual file operations:
1. Create temp dirs for /config and /etc/openclaw
2. Set test env vars
3. Run substitution logic
4. Verify output with grep
5. Cleanup temp dirs

### Key Files
- Entrypoint: `images/openclaw-nix/entrypoint.sh`
- Template: `images/openclaw-nix/config-template.json5`
- Command: `exec openclaw gateway --port 18789 "$@"`

## T6: OCI Image Build - Nix flake package

**Date:** 2026-02-21
**Status:** COMPLETED

### Build Command
```bash
nix build .#openclaw-nix-image
```

### File Structure
- `images/openclaw-nix/default.nix` - OCI image derivation
- `images/openclaw-nix/entrypoint.sh` - Entrypoint script (staged in git)
- `images/openclaw-nix/config-template.json5` - Config template (staged in git)

### Key Implementation Details

#### Image Tool Choice
Used `dockerTools.streamLayeredImage` instead of `buildLayeredImage`:
- Produces a streaming script rather than static tarball
- More memory-efficient for large images
- Consumes on-the-fly when piped to docker/podman

#### Required Git Staging
Nix flakes use git to determine source files. All referenced files MUST be staged:
```bash
git add images/openclaw-nix/default.nix
git add images/openclaw-nix/entrypoint.sh
git add images/openclaw-nix/config-template.json5
```

#### Package Input Pattern
In `flake.nix`, pass inputs explicitly to the image module:
```nix
openclawNixImage = import ./images/openclaw-nix {
  pkgs = sysPkgs;
  inherit inputs system;
};
```

Then access nix-openclaw packages:
```nix
openclawGateway = inputs.nix-openclaw.packages.${system}.openclaw-gateway;
```

#### Image Contents via buildEnv
```nix
contents = pkgs.buildEnv {
  name = "openclaw-rootfs";
  paths = [
    openclawGateway
    pkgs.curl pkgs.jq pkgs.git pkgs.python3 pkgs.uv pkgs.ffmpeg
    pkgs.github-cli pkgs.gemini-cli pkgs.nodejs_22
    pkgs.cacert pkgs.coreutils pkgs.bash pkgs.procps pkgs.tzdata
    entrypointScript
    configTemplate
  ];
  pathsToLink = [ "/bin" "/etc" "/share/zoneinfo" ];
};
```

#### Environment Variables
All per filesystem contract from decisions.md:
- `OPENCLAW_STATE_DIR=/state/openclaw`
- `OPENCLAW_CONFIG_PATH=/config/openclaw.json`
- `HOME=/state/home`
- `PATH=/state/bin:/state/npm/bin:/bin:/usr/bin`
- `NPM_CONFIG_PREFIX=/state/npm`
- `NPM_CONFIG_CACHE=/state/cache/npm`
- `XDG_CACHE_HOME=/state/cache`
- `UV_CACHE_DIR=/state/cache/uv`
- `PIP_CACHE_DIR=/state/cache/pip`
- `SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt`
- `TZ=America/Sao_Paulo`

#### Directory Creation in extraCommands
```nix
extraCommands = ''
  mkdir -p ./tmp ./var/tmp
  chmod 1777 ./tmp ./var/tmp
  mkdir -p ./config
  mkdir -p ./state ./state/home ./state/openclaw ./state/workspace ./state/bin ./state/npm ./state/cache
  mkdir -p ./logs
  # ... symlinks for timezone, /usr/bin/env, /bin/sh
'';
```

#### Image Metadata
```nix
config = {
  Cmd = [ "/entrypoint.sh" ];
  ExposedPorts = { "18789/tcp" = { }; };
  # NOTE: No User field for rootless podman compatibility
  Env = [ ... ];
};
name = "localhost/openclaw-nix";
tag = "dev";
```

### Verification
Image config JSON confirmed:
- Architecture: amd64
- OS: linux
- Cmd: /entrypoint.sh
- ExposedPorts: 18789/tcp
- Environment: All vars correctly set
- User: Not set (as required)
- RepoTag: localhost/openclaw-nix:dev

### Dependencies Included
- OpenClaw gateway from nix-openclaw flake
- Core tools: curl, jq, git, python3, uv, ffmpeg, github-cli, gemini-cli, nodejs_22
- Python requests library
- Supporting: cacert, coreutils, bash, procps, tzdata

### Tooling Pattern: writeShellScriptBin
For embedding entrypoint scripts:
```nix
entrypointScript = pkgs.writeShellScriptBin "entrypoint.sh" (builtins.readFile ./entrypoint.sh);
```
Then in extraCommands:
```nix
cp ${entrypointScript}/bin/entrypoint.sh ./entrypoint.sh
chmod +x ./entrypoint.sh
```

### Config Template Embedding
```nix
configTemplate = pkgs.writeTextFile {
  name = "config-template.json5";
  text = builtins.readFile ./config-template.json5;
  destination = "/etc/openclaw/config-template.json5";
};
```

EOF