# valoris-flow

Auto-fix loop for the Valoris app on hermes: Loki errors → GitHub issue → fix PR → review → QA → José merges.
Design and label state machine: `vibeflow.md` in the valoris repo.

**Where things run.** `scripts/` are no-agent cron scripts of the `irenicus` profile, executed inside the
hermes gateway pod (`/opt/data/profiles/irenicus/scripts/`): `valoris_logs_daily.py` (05:00, Loki digest →
jaheira card), `valoris_issues_daily.py` (06:00, irenicus triage card), `valoris_flow_router.py` (every 5 min,
GitHub labels + kanban board → next cards, feed relay). The agents work on the `sandbox-nix` host over ssh.
Each skill under `skills/` is installed only in the profile that runs it: log-triage and pr-test → jaheira,
issue-triage → irenicus, fix → valygar, pr-review → keldorn. Profiles without a Matrix feed user (keldorn)
post to the feed through irenicus with a `[profile]` prefix.

**Deploy.** `./sync.sh --check` shows drift between this directory and `~/Homelab/hermes` (the CephFS dir the
pod mounts as `/opt/data`); `./sync.sh --apply` copies the files and archives skill copies left in other
profiles. Live files belong to the pod user, so the script overwrites contents in place and never chmods them.
Router dry run inside the pod:
`kubectl -n apps exec deploy/hermes-agent-gateway -c gateway-multiplex -- sh -c 'cd /opt/data/profiles/irenicus/scripts && python3 valoris_flow_router.py --dry-run'`.

**Test.** `python3 -W error::ResourceWarning -m unittest discover -s tests -t .` from this directory. Stdlib
only; GitHub, Matrix and the `hermes` CLI are faked, and the kanban DB is a temp file built from
`tests/kanban_schema.sql` (DDL of hermes v0.22.6).
