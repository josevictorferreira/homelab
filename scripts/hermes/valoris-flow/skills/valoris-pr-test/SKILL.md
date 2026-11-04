---
name: valoris-pr-test
description: Verify that a reviewed valoris-flow fix PR really solves its issue (run specs, reproduce), then squash-merge it or send it back. Used by "Testar PR" cards.
---

# Valoris PR test

The card body has the PR, the issue and the cycle; parent results are irenicus' review
(approved) and valygar's handoff. Your question: does this PR really fix the issue,
without breaking anything? If yes, merge it. You do not fix code yourself.

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
6. Decide.
   - Pass: `gh pr merge <url> --squash --delete-branch`. Then make sure the issue is
     closed (`gh issue view <N> --json state`; if still open, `gh issue close <N> --comment "Fixed by <url>"`).
     If the merge fails (conflict, not mergeable), that is a failure: report it.
   - Fail: post one PR comment `**Test (jaheira): FAILED**` with the exact commands,
     their output (trimmed) and what is still broken. If the card says this is the last
     cycle, also `gh issue edit <N> --add-label needs-human`.

## Finish
Call `kanban_complete` exactly once:
- `summary`: commands run with pass/fail, and on failure exactly what valygar must fix
  (his REDO card receives this text).
- `metadata`: `{"verdict": "merged" | "failed", "tests": ["<command>: pass|fail", ...], "feed": "<feed line>"}`
- `feed`: ONE sentence in Brazilian Portuguese, e.g.
  `Testei o PR #57, a correção resolve a #51; fiz o merge e a issue foi fechada.` or
  `Testei o PR #57 e fiz um comentário lá: a spec nova não falha sem a correção.`

Never push commits, never edit the PR's code, never merge a PR that failed any step.
Never call `kanban_request_review`, `kanban_request_changes` or `kanban_create`.
