# OpenClaw Nix Browser - Learnings

## 2025-03-04: Task 4 - Image Build & Smoke QA

### Finding: streamLayeredImage + buildEnv Closure Issue

When using `dockerTools.streamLayeredImage` with a `buildEnv` in `contents`,
the buildEnv's dependencies may NOT be automatically included in the image.

**Problem:**
- `cliTools` buildEnv includes `pkgs.chromium`, `pkgs.fontconfig`, etc.
- Image builds successfully
- But chromium/fontconfig binaries are NOT in the final image
- Nix store only has 266 entries (expected 400+ with chromium deps)

**Root Cause:**
`streamLayeredImage` doesn't automatically follow buildEnv symlinks to include
the full closure of referenced packages. The `cliTools` buildEnv creates a
derivation that symlinks to other packages, but those packages' store paths
aren't being pulled into the image layers.

**Evidence:**
```bash
# Chromium not found
podman run --rm localhost/openclaw-nix:dev ls /bin/chromium
# ls: cannot access '/bin/chromium': No such file or directory

# Nix store missing chromium
podman run --rm localhost/openclaw-nix:dev ls /nix/store/ | grep chromium
# (no output)
```

### Successful Pattern from Build

The image DID include:
- openclaw-gateway (built from nix-openclaw overlay)
- Node.js toolchain (node, npm, npx)
- Python with pip
- Basic CLI tools (curl, jq, git, ffmpeg)
- OpenClaw binary at /bin/openclaw

### Tagging Issue

The `imageTag = "v${version}-v2"` didn't apply correctly - image was tagged as
`dev` instead of `v2026.3.2-v2`. Need to verify how the tag is being set in
the flake output.

