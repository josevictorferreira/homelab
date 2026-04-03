## 2026-04-03T17:40:00Z Task: init
Issues log initialized.

## 2026-04-03T18:30:00Z Issue
- Fixed placeholder npmDepsHash and integrity values in lossless-claw files.

## 2026-04-03T19:12:00Z Issue
- Fixed JSON syntax error in oci-images/openclaw-nix/lossless-claw-package-lock.json (missing comma after integrity in packages.node_modules/@sinclair/typebox).

## 2026-04-03T20:25:00Z Prior Task2 had permission issues
- Root cause: extensions/ dir from gateway copy has restrictive perms (555)
- Initial fix attempt failed because chmod wasn't applied before mkdir
- Correct fix: chmod -R u+w on extensions/ BEFORE trying to create subdirs
- Nix flake requires 'git add' for new files or modified files to be visible to the evaluation step when running 'make manifests'.

## 2026-04-03T21:08:33Z Issue
- Removed duplicate invalid controllers.main.rollingUpdate block (surge/unavailable) in modules/kubenix/apps/openclaw-nix.nix; kept maxSurge/maxUnavailable.
