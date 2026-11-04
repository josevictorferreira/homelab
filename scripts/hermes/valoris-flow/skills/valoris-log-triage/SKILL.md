---
name: valoris-log-triage
description: Turn the daily Valoris Loki error digest (the card body) into deduplicated GitHub issues on josevictorferreira/valoris. Used by the valoris-flow 05:00 logs-triage card.
---

# Valoris logs triage

The card body is a digest of the last 24h of Valoris errors from Loki, already grouped
by fingerprint by a script. Your job: make sure every real error group has exactly one
open GitHub issue with everything a developer needs to fix it. You do not fix anything
and you do not decide whether it is worth fixing (irenicus triages at 06:00).

## Environment
- Your terminal is an ssh session on the `sandbox-nix` host. `gh` and `git` are
  authenticated for `josevictorferreira/valoris`.
- Read-only code context: `/workspace/hermes/workspace/valoris` (run `git -C
  /workspace/hermes/workspace/valoris fetch -q origin && git -C ... checkout -q origin/main`
  first). Never commit there.
- More logs if a group needs context: `curl -sG http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/query_range --data-urlencode 'query={app="valoris-worker"} |= "<text>"' --data-urlencode limit=20`.

## Procedure, per group in the card body
1. Look for an existing issue with the fingerprint:
   `gh issue list -R josevictorferreira/valoris --state all --search "<fingerprint> in:body" --json number,state,title,closedAt`.
2. Open issue found: add one comment with the new window's occurrences, first/last seen
   and anything new in the message. Do not open a duplicate.
3. Closed issue found: open a new issue (step 4) whose body starts with
   `Regression of #<old>: still happening after it was closed.`
4. No issue: create one.
   - Title: `[auto] <ExceptionClass> in <JobClass or component>: <short message>` (≤ 90 chars).
   - Labels: `--label bug --label auto-triage` (create `auto-triage` once with
     `gh label create auto-triage --color 5319e7 -R josevictorferreira/valoris` if missing).
   - Body (English, markdown): summary, occurrences + first/last seen (UTC), queue/job,
     normalized message, backtrace, example job arguments, the source files from the
     backtrace with a one-line note on what each does (read them in the clone), and the
     last line exactly: `<!-- valoris-fingerprint: <fingerprint> -->`.
   - Never paste secrets, tokens, cookies or full request headers. URLs of scraped
     listing pages are fine.
5. Groups that are obviously the same root cause (same exception, same frame) may share
   one issue: mention every fingerprint marker in that issue's body.

## Finish
Call `kanban_complete` exactly once:
- `summary`: what you did, one line per group (`<fingerprint> -> #N created|commented|regression`).
- `metadata`: `{"issues_created": [N, ...], "issues_commented": [N, ...], "feed": "<feed line>"}`
- `feed`: ONE sentence in Brazilian Portuguese, first person, listing the issues you
  created, e.g. `Criei 2 issues no valoris a partir dos logs: #51 NetworkError na
  imobiliaria_perez (HTTP 403), #52 falha de DNS no imoveisjansen.` Use `""` if you only
  commented on existing issues or did nothing.

Never call `kanban_request_review` or `kanban_create`; the flow router creates the next
cards. Use `kanban_block` only if GitHub is unreachable or auth fails.
