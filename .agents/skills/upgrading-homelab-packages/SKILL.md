---
name: "upgrading-homelab-packages"
description: "Upgrade any homelab service: container image versions, helm chart versions, and GitHub-sourced Nix derivations. Resolves the latest stable version automatically when unspecified."
metadata:
  triggers: "upgrade, update version, bump version, update service, upgrade service, latest version, update image, upgrade app, update app, new version, rollover to"
allowed-tools:
  - Bash*
  - Read*
  - Edit*
  - Grep*
  - Glob*
compatibility: opencode
---

# Upgrading Homelab Packages

Use this skill whenever the user asks to upgrade/update a service in the homelab,
with or without an explicit target version.

## Version Resolution

If the user specified a version, use it verbatim. If not, resolve the latest
**stable** version yourself — never pick beta/alpha/rc.

### GitHub-hosted projects (most cases)

```bash
scripts/github-latest-release.sh owner/repo                  # latest stable tag
scripts/github-latest-release.sh owner/repo --list 10        # sanity-check the 10 newest
scripts/github-latest-release.sh owner/repo --match '^v2\.'  # constrain to a major line
```

The script excludes GitHub-marked prereleases/drafts AND tag names containing
`beta|alpha|rc|pre|preview|nightly|dev|canary|snapshot` (case-insensitive).

Watch for **version-scheme changes**: hermes switched from calendar tags
(`v2026.9.x`) to semver (`v0.21.6`) — don't assume the old scheme matches what's
published now.

### Container images without a GitHub release

Check the registry tags (Docker Hub API or GHCR UI) and pick the newest tag that
is not a prerelease, `latest`, or rolling. Note the tag format the app's `.nix`
file already uses (`v` prefix or not — bookorbit has no `v`, immich does).

## Digest Conventions (per-app, NOT repo-wide)

**The repo does not have one uniform digest convention.** Verified examples:

| App | Pins |
|---|---|
| keycloak, hindsight, hermes-agent | **linux/amd64 child** digest |
| immich, bookorbit | **multi-arch index** digest |

Before fetching the new digest, determine THIS app's convention by checking the
existing pin against the manifest list:

```bash
scripts/image-digests.sh <registry/repo>:<current-tag> --check sha256:<current-pin>
# → "your pin IS the amd64 child digest" or "... is the multi-arch index digest"
```

Then get the new tag's digests and pick the level that matches. Mixing levels
within an app's history makes verification and rollbacks confusing.

## Workflow

1. **Study the app's git history first** — past upgrades of the same app are the
   ground truth for digest level, tag format, which files get touched, and
   whether the Helm chart moves with the app:

   ```bash
   git log --oneline -10 -- modules/kubenix/apps/<app>.nix
   git log -p -3 -- modules/kubenix/apps/<app>.nix | less
   ```

2. **Locate ALL version references** — grep for the old version string across
   the app's `.nix` + `<app>-config.enc.nix`:
   - main image, init containers, sidecars
   - env vars that duplicate the version (immich has `IMMICH_VERSION` in its
     secrets file — an image bump alone leaves it stale)
   - companion manifests sharing the image (hermes: gateway + kanban files;
     hindsight: reaper CronJob inherits `apiImageRef` automatically)
   - **do NOT bump** intentional contract pins: hermes kanban compatibility gate
     stays at its plugin-contract baseline, not the deployed version

3. **Pre-flight breaking changes** for major/minor jumps:
   - Release notes + upgrading guide (e.g. keycloak `/docs/latest/upgrading/`)
   - Env vars still valid? (imgproxy v4 removed deprecated `IMGPROXY_*` vars)
   - DB requirements? (immich v3 requires VectorChord — verify extensions before deploying)
   - Removed features needing config cleanup? (searxng dropped the `tavily` engine)
   - Runtime-interpreter drift for apps with PVC-mounted deps? (hermes image
     python 3.13→3.14 broke native modules in the CephFS user-site)
   - Boot-time maintenance on slow storage? (hermes ran DB VACUUM at startup on
     CephFS; the startup watchdog killed it mid-VACUUM → crash loop. Fix was an
     env knob: `HERMES_STARTUP_WATCHDOG_TIMEOUT_S`)
   - Surface findings to the user BEFORE editing; don't silently assume fine.

4. **Fetch digests** per the app's convention (see above).

5. **Edit** every occurrence from step 2. For GitHub-sourced Nix derivations,
   the commit SHA shown on the release page:

   ```bash
   scripts/github-tag-hash.sh owner/repo <TAG>   # dereferences annotated tags
   ```

   Nix fetch hashes still come from the build error message (32-zero placeholder
   trick for chart sha256).

6. **Secrets files**: if you changed a `*-config.enc.nix`, delete that file's
   line from `manifests.lock` AND the stale `.k8s/*-config.enc.yaml` before
   `make manifests`, or the umanifests stage silently restores the old version.

7. **Regenerate**: `make manifests` (never individual stages). Confirm the
   `.k8s/` diff contains only expected version/hash changes.

8. **Commit BOTH the `.nix` and regenerated `.k8s/` files** — Flux reads git;
   an uncommitted `.k8s/` means the upgrade never deploys (blocky lesson).
   Stage by explicit pathspec when other sessions' work is in the tree, and
   check `git diff --cached --stat` before committing. Get user approval,
   then push (gitleaks pre-commit hook double-checks secrets).

9. **Verify the rollout** — and check Flux isn't suspended first:

   ```bash
   kubectl get kustomization flux-system -n flux-system -o jsonpath='{.spec.suspend}'
   kubectl rollout status deploy/<app> -n apps --timeout=600s   # or sts/
   kubectl logs <pod> -n apps --tail=50 | grep -iE 'error|started|version|migrat'
   ```

   Verify the version three ways when possible: startup banner in logs,
   in-pod/API check (immich `/api/server/version`), and the public endpoint.
   For stateful apps with DB migrations (keycloak), confirm migration lines:
   `migrated realm <x> to <version>`.

   **"Running" ≠ healthy for plugin-based apps**: hermes pods can run 2/2 while
   matrix-platform silently failed to load. Check that critical adapters/
   plugins actually started, not just container readiness.

### Rollout failure modes seen in this cluster

- **ResourceQuota exhaustion (apps ns)**: init containers without explicit
  limits inherit the LimitRange 2-CPU default → quota exceeded at rollout.
  Fix: explicit small `resources.limits` on init containers.
- **RWO PVC multi-attach**: single-replica apps with RWO PVCs block the new pod
  while the old one terminates. Use `maxSurge=0, maxUnavailable=1` (keep
  RollingUpdate — switching to `Recreate` mid-flight wedged Flux for 10 min).
- **Slow pulls look like hangs**: 2GB+ images pull 4-13 min on these nodes
  (`ContainerCreating` with Pulling events = healthy, keep waiting).
- **Cluster incidents masquerade as upgrade failures**: Ceph recovery slows
  CephFS-walking init containers (12+ min in Init); etcd timeouts delay volume
  mounts. Check node/Ceph health before blaming the version bump.

## Helm Chart Upgrades

Charts are pinned separately from app versions — chart `version` ≠ app version.
Policy from history: **keep the chart pinned across app upgrades unless there's
a reason** (immich stayed on chart 0.10.3 through v3.1→v3.3). Only bump the
chart deliberately:
- Chart's own releases often live in a separate repo (`cloudpirates/<app>-chart`)
- Major chart bumps can carry breaking values-schema changes (immich chart
  0.13.0 = common library v4→v5) — test-render with `helm template` first
- New/changed chart sha256: use 32-zero placeholder, read correct hash from the
  `make manifests` error
- Deployment **selector labels are immutable** — verify renders keep them
  identical before applying a chart bump

## Verification Checklist

- [ ] Digest level matches the app's existing convention (checked with `--check`)
- [ ] All version occurrences updated (image(s), init containers, env vars)
- [ ] Intentional contract pins NOT touched
- [ ] Breaking changes reviewed / surfaced to user
- [ ] `make manifests` clean; `.k8s/` diff = version changes only
- [ ] `.nix` + `.k8s/` both committed; staged set verified; no secrets
- [ ] Flux not suspended; rollout healthy; version confirmed in logs/API
- [ ] For plugin-based apps: critical adapters verified connected

## Known Traps

- **`latest` tags**: never used; always pin exact version + digest.
- **Multi-image apps**: update ALL (immich-style server+ML when ML enabled).
- **Version/tag suffix chains**: trace the full `version` → `imageTag` → manifest
  computation; double suffixes (`v1.2.3-v2-v2`) have happened.
- **Dead make targets**: `make images*` reference a removed script — use this
  skill's scripts.
- **Concurrent sessions**: commit only your files (pathspec), never `git add -A`.
- **Post-incident Flux suspension**: if upgrades "don't deploy", check
  `spec.suspend` on the flux-system kustomization and any incident docs before
  forcing reconciliation (a suspended Flux may be deliberate, tied to Ceph
  recovery runbooks).
