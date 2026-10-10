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

If the user specified a version, use it verbatim (including any `v` prefix rules below).
If not, resolve the latest **stable** version yourself — never pick beta/alpha/rc.

### GitHub-hosted projects (most cases)

```bash
scripts/github-latest-release.sh owner/repo                  # latest stable tag
scripts/github-latest-release.sh owner/repo --list 10        # sanity-check the 10 newest
scripts/github-latest-release.sh owner/repo --match '^v2\.'  # constrain to a major line
```

The script excludes GitHub-marked prereleases/drafts AND tag names containing
`beta|alpha|rc|pre|preview|nightly|dev|canary|snapshot` (case-insensitive).

### Container images without a GitHub release

Check the registry tags page (`registry.hub.docker.com/v2/repositories/<image>/tags`
or `ghcr.io` UI) and pick the newest tag that is not a prerelease, `latest`, or
rolling tag. Note the tag format the app's `.nix` file already uses (`v` prefix or not).

## Workflow

1. **Locate the app**: `modules/kubenix/apps/<app>.nix` (+ `<app>-config.enc.nix` for secrets).
   Grep for the old version string to find EVERY occurrence — main image, init
   containers, sidecars, and any startup scripts that pin the version.

2. **Pre-flight for breaking changes**: for major/minor jumps, fetch the upstream
   release notes / upgrading guide (e.g. `https://<project>.org/docs/latest/upgrading/`)
   and check against the app's configured features. Surface anything relevant to the
   user BEFORE editing; don't silently assume it's fine.

3. **Resolve the target version** (see above).

4. **Fetch digests/hashes** — the repo pins `tag@sha256:<digest>`:

   ```bash
   podman pull <registry>/<image>:<tag>
   podman inspect <registry>/<image>:<tag> --format '{{json .RepoDigests}}'
   ```

   **CRITICAL — digest convention**: the repo pins the **platform-specific amd64
   digest**, NOT the manifest-list digest. When two digests appear, confirm which
   convention the existing entry used and match it:

   ```bash
   # Compare: old digest in the .nix vs candidates from the manifest list
   podman manifest inspect <registry>/<image>:<tag> | jq -r '.manifests[] | select(.platform.architecture=="amd64") | .digest'
   ```

5. **Edit** every occurrence found in step 1. For GitHub-sourced Nix derivations
   (`fetchFromGitHub`, `fetchurl` of release assets), get the commit SHA GitHub
   shows on the release page:

   ```bash
   scripts/github-tag-hash.sh owner/repo <TAG>   # dereferences annotated tags too
   ```

   Nix fetch hashes still come from the build error message (placeholder trick);
   the commit SHA goes into `rev`/source URLs. Beware: some release asset URLs
   lack the `v` prefix (see AGENTS.md lesson).

6. **Regenerate**: `make manifests` (never run pipeline stages individually).
   Confirm `.k8s/` diff contains only the expected version/hash changes.

7. **Secret check, then commit/push** (with user approval per AGENTS.md rules):

   ```bash
   git add <files> && git diff --cached --stat   # verify exactly what's staged
   git commit && git push                         # gitleaks pre-commit hook runs
   ```

8. **Verify rollout** (Flux reconciles automatically after push):

   ```bash
   kubectl rollout status deploy/<app> -n apps --timeout=600s   # or sts/<app>
   kubectl get pods -n apps -l app.kubernetes.io/name=<app>
   kubectl logs <pod> -n apps --tail=50 | grep -iE 'error|started|version'
   ```

   Commit and push IMMEDIATELY once the upgrade is verified — an uncommitted
   upgrade gets reverted by Flux's next reconciliation.

## Helm Chart Upgrades

Charts are pinned by version + sha256 in `kubenix.lib.helm.fetch`. Chart versions
do NOT always match the app version — check the chart's own releases (often a
separate repo like `cloudpirates/<app>-chart`):

```bash
scripts/github-latest-release.sh cloudpirates/<app>-chart --list 5
```

For a NEW chart (or changed sha256), use a placeholder hash of 32 zeros and let
`make manifests` fail — the error message contains the correct `sha256:...`
(see AGENTS.md lesson on OCI chart hash resolution).

## Verification Checklist

- [ ] All image/hash occurrences updated (main, init containers, sidecars)
- [ ] Digests match the repo's existing pin convention (amd64 platform digest)
- [ ] Breaking changes from release notes reviewed / surfaced to user
- [ ] `make manifests` clean; `.k8s/` diff shows only version changes
- [ ] No secrets in staged diff (gitleaks hook double-checks)
- [ ] Pod healthy + logs clean after rollout
- [ ] Committed and pushed (git status clean for the app's files)

## Known Traps

- **`latest` tags**: never used in this repo; always pin exact versions + digest.
- **Node image caching**: `latest` stays stale even with `imagePullPolicy: Always` — moot once pinned by digest.
- **Multi-image apps**: immich-style apps have server + ML images; upgrade ALL.
- **Version/tag suffix chains**: trace the full `version` → `imageTag` → manifest computation before editing; double suffixes like `v1.2.3-v2-v2` have happened.
- **Dead make targets**: `make images` / `images-outdated` / `images-check` reference a removed `scripts/kubenix-image-updater` — use this skill's scripts instead.
- **Chart appVersion vs chart version**: the chart `version` line is what the sha256 pins; the app image tag is set separately in `values`.
