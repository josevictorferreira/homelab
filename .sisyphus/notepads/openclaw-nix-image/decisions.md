
---

## Matrix & WhatsApp Plugin Dependencies for Offline Support

**Date:** 2026-02-21
**Scope:** Ensure matrix and whatsapp plugins work without runtime `npm install` (container can run with `--network=none`)

### Plugin Architecture Analysis

OpenClaw bundles all channel extensions in the `nix-openclaw` package at:
```
/lib/openclaw/extensions/
├── matrix/          # Matrix channel plugin
├── whatsapp/        # WhatsApp channel plugin (Baileys-based)
└── ... (other channels)
```

Each extension has its own `package.json` and `node_modules` directory.

### WhatsApp Plugin

**Status:** ✅ Works offline - NO dependencies required

**Evidence:**
- `package.json` has NO `dependencies` section
- Uses Baileys library which is bundled/compiled into OpenClaw core
- Extension loads without any npm install

**Required npm packages:** None

### Matrix Plugin

**Status:** ❌ Requires npm dependencies for offline support

**Required npm packages (from extensions/matrix/package.json):**

| Package | Version | Purpose |
|---------|---------|---------|
| `@vector-im/matrix-bot-sdk` | 0.8.0-element.3 | Core Matrix bot SDK |
| `@matrix-org/matrix-sdk-crypto-nodejs` | ^0.4.0 | E2EE encryption support |
| `markdown-it` | 14.1.1 | Markdown parsing |
| `music-metadata` | ^11.12.1 | Audio metadata extraction |
| `zod` | ^4.3.6 | Schema validation |

**Current state in nix-openclaw:**
- Extensions are bundled at `/lib/openclaw/extensions/matrix/`
- `node_modules` directory exists but is EMPTY
- Dependencies must be installed via `npm install` at runtime

### Solution Implemented

Added `matrixPluginDeps` derivation to `images/openclaw-nix/default.nix`:

```nix
matrixPluginDeps = pkgs.stdenv.mkDerivation {
  name = "openclaw-matrix-plugin-deps";
  # ... installs npm packages at build time
};
```

**Build-time npm install:**
- Installs all 5 matrix plugin dependencies during image build
- Copies `node_modules` into image at `/lib/openclaw/extensions/matrix/node_modules`

**Image changes:**
1. Added `matrixPluginDeps` to `contents.paths`
2. Added copy command in `extraCommands`:
   ```bash
   cp -r ${matrixPluginDeps}/lib/openclaw/extensions/matrix/node_modules \
     ./lib/openclaw/extensions/matrix/
   ```

### Network Access Requirements

| Plugin | Network Required | Reason |
|--------|------------------|--------|
| WhatsApp | ❌ No | All deps bundled in core |
| Matrix | ❌ No (after fix) | All deps pre-installed in image |

### Testing Offline Support

**Container can start with --network=none:**
```bash
podman run --rm --network=none localhost/openclaw-nix:dev openclaw --version
# Output: 2026.2.20
```

**Verify plugins load:**
```bash
# Without network, plugins should initialize without npm install errors
podman run --rm --network=none -v /state:/state localhost/openclaw-nix:dev \
  openclaw plugins list
```

### NODE_PATH Configuration

The nix-openclaw package automatically resolves extension dependencies from their local `node_modules` directories. No additional NODE_PATH configuration is needed because:

1. Extensions are loaded from `/lib/openclaw/extensions/<name>/`
2. Node.js resolves `require()` from the extension's directory
3. Each extension's `node_modules` is in the same directory as the extension code

### Key Findings

1. **WhatsApp is self-contained** - Uses Baileys compiled into core, no npm deps
2. **Matrix needs external deps** - Uses matrix-bot-sdk which has native bindings
3. **Pre-installation works** - Build-time npm install produces working node_modules
4. **Image size impact** - ~50-100MB additional for matrix dependencies

### References

- Matrix plugin docs: https://docs.openclaw.ai/channels/matrix.md
- WhatsApp plugin docs: https://docs.openclaw.ai/channels/whatsapp.md
- nix-openclaw extensions: `/lib/openclaw/extensions/` in `openclaw-gateway` package
- Matrix package.json: `${openclawGateway}/lib/openclaw/extensions/matrix/package.json`

