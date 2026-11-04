---
name: valoris-issue-triage
description: Daily triage of open GitHub issues on josevictorferreira/valoris; close the ones code can't fix and hand the rest to the valoris-flow with the `triaged` label. Used by the 06:00 issue-triage card.
---

# Valoris issue triage

Decide, for every open issue of `josevictorferreira/valoris` that is not labeled
`triaged`, whether a code change in the repo can fix it. You do not fix anything and you
do not create kanban cards: the `triaged` label is what hands an issue to the fix stage
(the flow router creates valygar's fix card from it).

## Environment
- Your terminal is an ssh session on the `sandbox-nix` host; `gh` and `git` are
  authenticated. Read-only clone for code context: `/workspace/hermes/workspace/valoris`
  (`git fetch -q origin && git checkout -q origin/main` first; never commit there).
- List: `gh issue list -R josevictorferreira/valoris --state open --search "-label:triaged" --json number,title,labels,body,createdAt,comments --limit 50`.

## Decide, per issue
Close it (`gh issue close <N> --reason "not planned" --comment "<why, 1-3 sentences>"`) when:
- it is not fixable by code: third-party site down/blocking us (HTTP 403/5xx from a
  scraped site with no parser/retry bug), DNS of an external host, quota/capacity of
  storage, power or node outage, database restarts;
- it was a momentary blip: few occurrences in a short window, no recurrence in the
  last 48h (check the comments jaheira adds every day);
- it duplicates another open issue (`--reason "not planned"`, comment `Duplicate of #M`).

Skip it (no label, no comment) when an open PR already addresses it:
`gh pr list -R josevictorferreira/valoris --state open --search "<N> in:body"`.

Accept it otherwise: a recurring error with a clear code path (parser bug, missing
retry/rescue, wrong data handling, crash in our code). Add the label `triaged`
(`gh issue edit <N> --add-label triaged`; create the label once if missing). When the
fix is not obvious, add one comment with your hypothesis and the files to look at:
valygar reads the issue.

Prefer closing over accepting when in doubt about whether code can fix it; prefer
accepting when it is a real bug, even if small.

## Finish
Call `kanban_complete` exactly once:
- `summary`: one line per issue: `#N accepted|closed|skipped: <reason>`.
- `metadata`: `{"feed": "<feed line>"}`
- `feed`: ONE sentence in Brazilian Portuguese, first person, only about real actions,
  e.g. `Triei 4 issues do valoris: aceitei #51 e #53 para correção, fechei #52 (DNS
  externo) e #54 (instabilidade momentânea).` Use `""` when there was nothing to triage.

Never call `kanban_request_review` or `kanban_create`.
