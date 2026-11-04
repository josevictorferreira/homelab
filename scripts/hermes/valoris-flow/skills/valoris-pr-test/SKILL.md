---
name: valoris-pr-test
description: Verify that a reviewed valoris-flow fix PR really solves its issue (run specs, reproduce), then mark it ready for José's merge or send it back. Used by "Testar PR" cards.
---

# Valoris PR test

The card body has the PR, the issue and the cycle; parent result is keldorn's review
(approved). Your question: does this PR really fix the issue,
without breaking anything? If yes, label it ready for José to merge. You do not fix code
yourself and you never merge.

## Environment
- Your terminal is an ssh session on `sandbox-nix`; `gh`/`git` are authenticated.
- Worktree: `/workspace/hermes/workspace/valoris-wt/test-pr-<P>`:
  `git -C /workspace/hermes/workspace/valoris fetch -q origin && git -C /workspace/hermes/workspace/valoris worktree add -f --detach <wt> origin/<headRefName>`
  (remove it with `git worktree remove --force <wt>` when you finish).
- Run backend commands inside the dev shell (it starts Postgres):
  `/workspace/hermes/workspace/bin/valoris-dev <wt> <cmd> [args...]` (it stops that shell's
  Postgres afterwards; never call `nix develop` directly, every call leaks a Postgres server).
  Each call boots a fresh database (~5-8 min), so batch work into one call, e.g.
  `valoris-dev <wt> sh -c 'bundle install --quiet && bundle exec rspec <specs> && bundle exec rubocop <files>'`
- Gems live in `<checkout>/backend/.bundle`. In every new worktree seed them first, then
  top up: `cp -a /workspace/hermes/workspace/valoris/backend/.bundle <wt>/backend/` and
  `bundle install --quiet` (inside the dev shell). Call `kanban_heartbeat` during long runs.

## Procedure
1. `gh issue view <N> --comments` and `gh pr view <url> --json files,body,mergeable,headRefName`.
2. Prove the fix: the spec valygar added must fail on `origin/main` and pass on the PR
   branch. Copy the new/changed spec file into a second worktree detached at
   `origin/main` and run it there, then run it in the PR worktree. If no spec
   reproduces the issue, that is a failure.
3. Regression: run the specs of every touched domain (`bundle exec rspec spec/domains/<domain>`),
   plus `bundle exec rubocop` on the changed files.
4. When the issue has concrete inputs (a listing URL, job arguments), exercise the
   changed code path with them in `bin/rails runner` against the dev database, if it
   can run without production credentials. Skip this step if it cannot.
5. CI: `gh pr checks <url>` must not have failing checks (pending: wait up to 10 minutes,
   `kanban_heartbeat` while waiting).
6. Decide, then post ONE PR comment (`gh pr comment <url> --body-file <file>`) starting exactly with
   `**Test (jaheira): PASSED**` or `**Test (jaheira): FAILED**` (the flow parses that line), listing the
   commands you ran and their trimmed output; on failure, say exactly what is still broken. Then set the
   verdict label (this is what moves the flow on):
   - Pass: `gh api -X POST repos/josevictorferreira/valoris/issues/<P>/labels -f "labels[]=auto-qa-passed"`.
     José merges; you do not.
   - Fail: `gh api -X POST repos/josevictorferreira/valoris/issues/<P>/labels -f "labels[]=auto-qa-failed"`.
     If the card says this is the last cycle, also add `needs-human` to the issue
     (`gh api -X POST repos/josevictorferreira/valoris/issues/<N>/labels -f "labels[]=needs-human"`).
   A PR that is not mergeable (conflicts) is a failure.

## Finish
Call `kanban_complete` exactly once:
- `summary`: commands run with pass/fail, and on failure exactly what valygar must fix
  (his REDO card receives this text).
- `metadata`: `{"tests": ["<command>: pass|fail", ...], "feed": "<feed line>"}`
- `feed`: ONE sentence in Brazilian Portuguese, e.g.
  `Testei o PR #57, a correção resolve a #51; está pronto para merge: https://github.com/josevictorferreira/valoris/pull/57` or
  `Testei o PR #57 e fiz um comentário lá: a spec nova não falha sem a correção.`

Never push commits, never edit the PR's code, never merge any PR, never close the issue.
Never call `kanban_request_review`, `kanban_request_changes` or `kanban_create`.
