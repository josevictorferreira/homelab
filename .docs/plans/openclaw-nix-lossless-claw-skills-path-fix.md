# OpenClaw Nix Lossless-Claw Skills Path Fix

## Problem

`openclaw-nix` starts with the `lossless-claw` plugin enabled, and the configured agents (`mel`, `kira`, `luna`, and `spike`) reference the `lossless-claw` skill. At runtime, OpenClaw cannot load that bundled skill because the image does not contain the path declared by the plugin manifest.

The plugin manifest in the running image declares:

```json
"skills": ["skills/lossless-claw"]
```

OpenClaw resolves that relative to the plugin root, so it expects this path to exist in the image:

```text
/lib/openclaw/dist/extensions/lossless-claw/skills/lossless-claw
```

In the live pod, the `lossless-claw` plugin directory only contains `index.js`, `node_modules/`, `openclaw.plugin.json`, and `package.json`. The `skills/` directory is missing from both:

```text
/lib/openclaw/dist/extensions/lossless-claw/skills
/lib/openclaw/extensions/lossless-claw/skills
```

## Root Cause

The upstream npm package `@martian-engineering/lossless-claw@0.9.2` includes the expected skill tree:

```text
skills/lossless-claw/SKILL.md
skills/lossless-claw/references/architecture.md
skills/lossless-claw/references/config.md
skills/lossless-claw/references/diagnostics.md
skills/lossless-claw/references/recall-tools.md
skills/lossless-claw/references/session-lifecycle.md
```

The Nix image build drops it. In `oci-images/openclaw-nix/default.nix`, `lossless-claw` is extracted from the npm tarball through a special-case path that copies only:

```text
package/dist/index.js
package/openclaw.plugin.json
package/package.json
```

The generic plugin copy loop would normally copy `skills/`, but it explicitly skips `lossless-claw` because that plugin is handled as a prebuilt npm package. The special-case block never copies `package/skills`, so the final Nix store rootfs lacks the skill path declared by `openclaw.plugin.json`.

## Proposed Fix

Update the special `lossless-claw` extraction block in `oci-images/openclaw-nix/default.nix` to copy the npm package's `skills/` directory into the runtime plugin paths.

The required runtime path is:

```text
$out/lib/openclaw/dist/extensions/lossless-claw/skills/lossless-claw
```

Also copy it into the compatibility mirror path:

```text
$out/lib/openclaw/extensions/lossless-claw/skills/lossless-claw
```

Keep the existing `lossless-claw` skip in the generic copy loop. The plugin is intentionally special-cased because it comes from the npm tarball, so the minimal fix is to make that special-case complete.

Conceptual patch:

```sh
if [ -d /tmp/lossless-extract/package/skills ]; then
  cp -r /tmp/lossless-extract/package/skills \
    "$out/lib/openclaw/dist/extensions/lossless-claw/"

  cp -r /tmp/lossless-extract/package/skills \
    "$out/lib/openclaw/extensions/lossless-claw/"
fi
```

Place this before `rm -rf /tmp/lossless-extract`.

## Implementation Plan

1. Edit `oci-images/openclaw-nix/default.nix` to copy `/tmp/lossless-extract/package/skills` into both `dist/extensions/lossless-claw/` and `extensions/lossless-claw/`.
2. Build the image locally and verify the Nix store rootfs contains `dist/extensions/lossless-claw/skills/lossless-claw/SKILL.md`.
3. Load/run the built image locally and verify the same path exists inside the container.
4. Push the rebuilt image to GHCR with an explicit version tag.
5. Update `modules/kubenix/apps/openclaw-nix.nix` to reference the new tag/digest.
6. Run `make manifests` and verify the generated manifest references the new image digest.
7. Deploy through the normal GitOps path or apply only the generated `openclaw-nix` manifest if a break-glass rollout is explicitly approved.
8. Verify the running pod contains the skill path and OpenClaw no longer logs `plugin skill path not found (lossless-claw)`.

## Validation Commands

After building the image, verify the rootfs/container contains:

```sh
ls /lib/openclaw/dist/extensions/lossless-claw/skills/lossless-claw/SKILL.md
ls /lib/openclaw/dist/extensions/lossless-claw/skills/lossless-claw/references
```

After deployment, verify in the pod:

```sh
kubectl exec -n apps deploy/openclaw-nix -c main -- \
  ls /lib/openclaw/dist/extensions/lossless-claw/skills/lossless-claw/SKILL.md
```

Check logs for absence of the old missing-path warning:

```sh
kubectl logs -n apps deploy/openclaw-nix -c main | grep 'plugin skill path not found (lossless-claw)'
```

## Risks And Notes

- This should not require any CephFS, PVC, or Ceph CRD changes.
- Do not edit `.k8s/*.yaml` directly; regenerate with `make manifests`.
- Do not use `latest`; keep an explicit image tag and digest.
- Do not remove the generic loop's `lossless-claw` skip unless a broader plugin packaging refactor is intentionally planned.
