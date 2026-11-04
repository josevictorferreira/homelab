---
name: valoris-fix
description: Fix one triaged GitHub issue of josevictorferreira/valoris and open (or update, on REDO cards) the PR. Used by valoris-flow fix cards ("#N Corrigir:" and "REDO #<PR> ciclo <n>:").
---

# Valoris fix

The card body names the issue. On a REDO card it also names the existing PR and carries
the review/test comment that rejected the previous attempt (the parent card result has the
reviewer's or tester's summary too). Ship the smallest correct fix with tests, push it, and
hand the PR to the flow: GitHub labels are how the flow moves on, so set them exactly as below.

## Environment
- Your terminal is an ssh session on the `sandbox-nix` host; `gh` and `git` are
  authenticated. Ignore `$HERMES_KANBAN_WORKSPACE`; work in a git worktree instead:
  - base clone: `/workspace/hermes/workspace/valoris` (`git -C <base> fetch -q origin`)
  - worktree: `/workspace/hermes/workspace/valoris-wt/issue-<N>`
    - first attempt: `git -C <base> worktree add -B fix/issue-<N> <wt> origin/main`
    - REDO: reuse the worktree if it exists, else
      `git -C <base> worktree add <wt> fix/issue-<N>`; then `git pull --rebase origin fix/issue-<N>`.
- Before coding read `AGENTS.md`, `backend/AGENTS.md` and the `AGENTS.md` of the domain
  you touch. Follow their conventions (RBS inline comments, RSpec only, domain layout).
- Run every backend command inside the dev shell (it starts Postgres):
  `/workspace/hermes/workspace/bin/valoris-dev <wt> <cmd> [args...]` (it stops that shell's
  Postgres afterwards; never call `nix develop` directly, every call leaks a Postgres server).
  Each call boots a fresh database (~5-8 min), so batch work into one call, e.g.
  `valoris-dev <wt> sh -c 'bundle install --quiet && bundle exec rspec <specs> && bundle exec rubocop <files>'`
  e.g. `bundle exec rspec spec/path_spec.rb`, `bundle exec rubocop <files>`.
  Gems live in `<checkout>/backend/.bundle`. In a new worktree seed them first, then
  top up: `cp -a /workspace/hermes/workspace/valoris/backend/.bundle <wt>/backend/` and
  `bundle install --quiet` (inside the dev shell). The first `nix develop` of a new
  flake.lock can take ~30 min; call `kanban_heartbeat` while it runs.

## Procedure
1. `gh issue view <N> -R josevictorferreira/valoris --comments`. Reproduce the failure in
   a spec first (it must fail before your change, pass after).
2. Fix the root cause in our code. Keep the diff scoped to the issue: no drive-by
   refactors, no formatting churn. If the right fix is a retry/rescue, make it bounded
   and log it.
3. `rspec` for the touched specs and `rubocop` for the touched files must pass. CI runs
   rubocop on the whole backend, so do not leave offenses.
4. Commit (`fix(<domain>): <what> (#<N>)`), `git push -u origin fix/issue-<N>`.
5. First attempt: `gh pr create -R josevictorferreira/valoris --base main --head fix/issue-<N> --label auto-pr --title "fix(<domain>): <what>" --body "<root cause, fix, tests>\n\nCloses #<N>"`.
   The label `auto-pr` and the `Closes #<N>` line are how the flow finds the PR: both are required.
   Do not request a reviewer; the flow assigns keldorn through a kanban card.
   REDO: push to the same branch, add one PR comment listing how each finding was addressed, then
   clear the verdict labels so the new commits get a fresh review:
   `gh api -X DELETE repos/josevictorferreira/valoris/issues/<P>/labels/<label>` for each of
   `auto-review-changes`, `auto-review-ok`, `auto-qa-failed`, `auto-qa-passed` (a 404 for a label the PR
   does not have is fine).
6. Confirm the commit is on the remote (`git ls-remote origin fix/issue-<N>`) and that
   `gh pr view <url> --json state` is OPEN.

If the issue cannot be fixed by code after all (external site, infrastructure,
already fixed on main), do not open a PR: comment the evidence on the issue, close it
with `gh issue close <N> --reason "not planned"`, and complete (the closed issue ends its flow).

## Finish
Call `kanban_complete` exactly once:
- `summary`: root cause, what changed, tests run (on REDO: how each finding was addressed).
- `metadata`: `{"changed_files": [...], "tests": ["<command>", ...], "feed": "<feed line>"}`
- `feed`: ONE sentence in Brazilian Portuguese, first person, e.g.
  `Criei o PR #57 no valoris para resolver a #51 (NetworkError na imobiliaria_perez: o
  extrator não tratava HTTP 403): https://github.com/josevictorferreira/valoris/pull/57`
  or on REDO `Atualizei o PR #57 com as correções pedidas na revisão.`

Never call `kanban_request_review` or `kanban_create`; never merge; never push to main.
Use `kanban_block` only for things José must decide or provide.
