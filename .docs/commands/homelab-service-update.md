---
name: "homelab-service-update"
description: "Update any app's container image version in the kubenix-based Kubernetes homelab."
---

# Update Container Image Version

Use this prompt to update any app's container image version in the kubenix-based Kubernetes homelab.

---

## PROMPT TEMPLATE

```
Update the {APP_NAME} container image(s) to version "{NEW_VERSION}".

## TASK BREAKDOWN

1. **Locate Configuration**
   - Find the app in: `modules/kubenix/apps/{app-name}.nix`
   - Identify ALL container images used by the app (main app, sidecars, init containers)
   - Note the current image format: `image.tag = "vX.Y.Z@sha256:...";`

2. **Fetch Image Digests** (CRITICAL - DO NOT SKIP)
   
   For each image, get the SHA256 digest for the NEW_VERSION:
   
   **Method 1 - GitHub Container Registry (ghcr.io):**
   ```bash
   # Navigate to the package page
   https://github.com/{owner}/{repo}/pkgs/container/{image-name}/versions
   
   # Find the tag, click to see full digest
   # Format: sha256:64hexchars
   ```
   
   **Method 2 - Docker Hub:**
   ```bash
   # Use docker hub API or pull and inspect
   docker pull {image}:{tag}
   docker inspect {image}:{tag} --format='{{index .RepoDigests 0}}'
   ```
   
   **Method 3 - Crane (if available):**
   ```bash
   crane digest {registry}/{image}:{tag}
   ```

   ⚠️ **EDGE CASE: Multi-arch images**
   - If the image is multi-arch (manifest list), you need the PLATFORM-SPECIFIC digest
   - For amd64/linux: Look for the digest associated with "linux/amd64" platform
   - The manifest list digest ≠ platform-specific digest
   - WRONG: `sha256:abc...` (manifest list)
   - RIGHT: `sha256:def...` (linux/amd64 layer)

3. **Update Image References**
   
   Format: `"v{VERSION}@sha256:{DIGEST}"`
   
   Example:
   ```nix
   # BEFORE
   image.tag = "v2.3.1@sha256:f8d06a32b1b2a81053d78e40bf8e35236b9faefb5c3903ce9ca8712c9ed78445";
   
   # AFTER
   image.tag = "v2.5.0@sha256:6c011eaa315b871f3207d68f97205d92b3e600104466a75b01eb2c3868e72ca1";
   ```

4. **Regenerate Manifests**
   ```bash
   make manifests
   ```

## CRITICAL GOTCHAS & EDGE CASES

1. **Multiple Images per App**
   - Some apps have 2+ images (e.g., immich has server + machine-learning)
   - Update ALL images, not just the main one
   - Check for: main container, init containers, sidecars

2. **Digest Format**
   - MUST include full 64-character sha256 hash
   - Format is: `tag@sha256:digest` (NOT just `sha256:digest`)
   - The @ symbol is required

3. **Registry Differences**
   - ghcr.io (GitHub): `/pkgs/container/{name}/versions` page shows digests
   - Docker Hub: Use `docker inspect` or hub.docker.com API
   - gcr.io, quay.io: Use `skopeo` or `crane`

4. **Version Tag Formats**
   - Some use `v1.2.3`, others use `1.2.3`
   - Check the registry - use EXACTLY what's published
   - Don't guess: verify on the registry page

5. **Helm Chart Images**
   - Some apps use Helm charts with subcharts
   - Images may be defined in `values` section, not direct `image.tag`
   - Check: `helm.values.image.tag` or similar paths

6. **Image Pull Policy**
   - If `imagePullPolicy = "Always"` is set, digest is still required for reproducibility
   - Don't remove digest even if policy is Always

7. **Private Registries**
   - If image is from private registry, ensure auth is configured
   - Check `imagePullSecrets` if needed

8. **Breaking Changes**
   - New versions may require config changes
   - Check upstream release notes for:
     - New required environment variables
     - Deprecated features
     - Config format changes

## VERIFICATION CHECKLIST

- [ ] All images updated to new version
- [ ] All digests are platform-specific (not manifest list)
- [ ] Format is exactly: `"tag@sha256:digest"`
- [ ] `make manifests` completes without errors
- [ ] Generated YAML in `.k8s/` shows new image references

## CURRENT STATE

App: {APP_NAME}
Current Version: {CURRENT_VERSION}
Target Version: {NEW_VERSION}
Registry: {REGISTRY}
```

---

## How to Use

Replace the placeholders:
- `{APP_NAME}` - e.g., "immich", "ollama"
- `{NEW_VERSION}` - e.g., "v2.5.0", "1.21.0"
- `{CURRENT_VERSION}` - current version from the .nix file
- `{REGISTRY}` - e.g., "ghcr.io", "docker.io"

### Example Usage

```
Update the immich container image(s) to version "v2.5.0".

## CURRENT STATE
App: immich
Current Version: v2.3.1
Target Version: v2.5.0
Registry: ghcr.io
```

---

## Lessons Learned from Implementation

1. **Multi-arch manifest trap**: The registry returns a manifest list digest, but you need the platform-specific digest (linux/amd64). Browse the GitHub Packages UI to find the correct one.

2. **Multiple images**: Apps like immich have separate images (server + ML) - both need updating.

3. **Digest source**: GitHub's container registry UI at `/pkgs/container/{name}/versions` is the most reliable way to get the exact digest for a specific platform.

4. **Format strictness**: The format must be exactly `"tag@sha256:digest"` - the @ symbol and full 64-char hash are required.

5. **Submodule pattern differences**:
   - Apps use either `submodule = "helm"` or `submodule = "release"`
   - `release` submodule handles image digests correctly (like blocky)
   - `helm` submodule may have chart-specific quirks and buggy templates
   - **Always check the submodule type first** - if app uses `helm`, consider converting to `release` if encountering image issues

6. **Chart template bugs**:
   - Some Helm charts have buggy image templates (e.g., searxng's boilerplate subchart)
   - The `digest` field may not work due to template bugs - only `tag` may render correctly
   - **Test before implementing**: Use `helm template <release> <chart> -f test-values.yaml` to verify which values actually work
   - This is faster than repeatedly running `make manifests` to debug

7. **Testing Helm behavior**:
   ```bash
   # Quick test of Helm chart with specific values
   cat > test-values.yaml << 'EOF'
   image:
     tag: "v1.2.3@sha256:..."
   EOF
   helm template test searxng -f test-values.yaml 2>&1 | grep image:
   ```

8. **Cleanup after debugging**:
   - Remove all test files created during debugging: `rm -f test*.yaml`
   - Remove downloaded Helm charts: `rm -rf searxng boilerplate *.tgz`
   - Clean Helm cache if needed: `rm -rf ~/.cache/helm/*`
   - This prevents repository pollution and confusion in future tasks
