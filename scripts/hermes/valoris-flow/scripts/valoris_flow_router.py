#!/usr/bin/env python3
"""Valoris flow router (no-agent cron, every minute).

For every flow card that completed since the last tick:
  * posts its `metadata.feed` line (if any) to the Matrix feed room as the card's agent;
  * creates the next stage's card (fix -> review -> test, rejections -> REDO fix).
It also announces, once, any flow card that ends up blocked. Prints nothing (silent tick).
"""
import json

from valoris_flow import MAX_CYCLES, REPO, board, create_card, locked_state, post_feed, run


def fix_body(issue, title, cycle, prev_fix=None, rejection=None, pr=None):
    lines = [f"Issue: https://github.com/{REPO}/issues/{issue} ({title})",
             f"Cycle: {cycle}/{MAX_CYCLES}"]
    if prev_fix:
        lines += [f"REDO of card {prev_fix}. The previous attempt was rejected; the parent card",
                  "results below carry the reviewer/tester findings. Address every finding.",
                  f"Keep working on the existing PR {pr}: push new commits to its branch, do not open a new PR."]
        if rejection:
            lines += ["", "Rejection summary:", rejection]
    return "\n".join(lines)


def stage_body(chain, cycle):
    issue, pr = chain["issue"], chain["pr"]
    lines = [f"PR: {pr}", f"Issue: https://github.com/{REPO}/issues/{issue} ({chain['title']})",
             f"Cycle: {cycle}/{MAX_CYCLES}"]
    if cycle >= MAX_CYCLES:
        lines.append(f"This is the last cycle: if you reject, also add the label `needs-human` to issue #{issue}.")
    return "\n".join(lines)


def start_fix(state, source_task, issue, title, cycle, parents=(), prev_fix=None, rejection=None):
    """Create the fix card for `issue`; `source_task` is the card that triggered it."""
    if cycle == 1:
        state["chains"][str(issue)] = {"issue": issue, "title": title, "pr": None, "last_fix": None}
    chain = state["chains"][str(issue)]
    chain.update(cycle=cycle, active=True)
    name = f"#{issue} Corrigir: {title}"
    if prev_fix:
        name = f"REDO #{prev_fix}: {name}"
    create_card(state, "fix", name, fix_body(issue, title, cycle, prev_fix, rejection, chain["pr"]),
                f"valoris-flow:fix:{issue}:{source_task}", parents, issue=issue)


def on_completed(state, task_id, card, meta, summary):
    stage = card["stage"]
    if stage == "issues":
        for item in meta.get("accepted", []):
            issue = item["number"] if isinstance(item, dict) else int(item)
            title = item.get("title", f"issue {issue}") if isinstance(item, dict) else f"issue {issue}"
            if not state["chains"].get(str(issue), {}).get("active"):
                start_fix(state, task_id, issue, title, 1)
        return
    if stage == "logs":
        return

    chain = state["chains"][str(card["issue"])]
    if stage == "fix":
        if not meta.get("pr_url"):  # not fixable by code: valygar closed/commented the issue
            chain["active"] = False
            return
        chain["pr"], chain["last_fix"] = meta["pr_url"], task_id
        create_card(state, "review", f"Revisar PR {meta['pr_url'].rsplit('/', 1)[-1]} (issue #{chain['issue']})",
                    stage_body(chain, chain["cycle"]),
                    f"valoris-flow:review:{task_id}", [task_id], issue=chain["issue"])
        return

    approved = meta.get("verdict") in ("approved", "merged")
    if approved and stage == "review":
        create_card(state, "test", f"Testar PR {chain['pr'].rsplit('/', 1)[-1]} (issue #{chain['issue']})",
                    stage_body(chain, chain["cycle"]),
                    f"valoris-flow:test:{task_id}", [task_id, chain["last_fix"]], issue=chain["issue"])
    elif approved:  # test passed and jaheira merged
        chain["active"] = False
    elif chain["cycle"] >= MAX_CYCLES:
        chain["active"] = False
        post_feed("irenicus", f"A issue #{chain['issue']} foi recusada {MAX_CYCLES} vezes e precisa de você: {chain['pr']}",
                  f"vf-cap-{task_id}")
    else:
        start_fix(state, task_id, chain["issue"], chain["title"], chain["cycle"] + 1,
                  parents=[task_id, chain["last_fix"]], prev_fix=chain["last_fix"], rejection=summary)


def announce_blocked(state, db):
    for task_id, card in state["cards"].items():
        if card.get("blocked_notified"):
            continue
        row = db.execute("select status, assignee, title, last_failure_error from tasks where id = ?",
                         (task_id,)).fetchone()
        if row and row[0] == "blocked":
            reason = (row[3] or "sem motivo registrado").splitlines()[0][:200]
            post_feed(row[1], f"Travei no card {task_id} ({row[2]}): {reason}", f"vf-blocked-{task_id}")
            card["blocked_notified"] = True
        elif row and row[0] != "blocked":
            card.pop("blocked_notified", None)


def main():
    with locked_state() as state:
        db = board()
        if state["cursor"] is None:  # first run: start from now, never replay history
            state["cursor"] = db.execute("select coalesce(max(id), 0) from task_events").fetchone()[0]
            return
        events = db.execute("select id, task_id from task_events where id > ? and kind = 'completed' order by id",
                            (state["cursor"],)).fetchall()
        for event_id, task_id in events:
            card = state["cards"].get(task_id)
            if card:
                row = db.execute("select metadata, summary from task_runs where task_id = ? and outcome = 'completed' "
                                 "order by id desc limit 1", (task_id,)).fetchone()
                meta = json.loads(row[0]) if row and row[0] else {}
                if meta.get("feed"):
                    profile = db.execute("select assignee from tasks where id = ?", (task_id,)).fetchone()[0]
                    post_feed(profile, meta["feed"], f"vf-done-{event_id}")
                on_completed(state, task_id, card, meta, row[1] if row else None)
            state["cursor"] = event_id
        announce_blocked(state, db)


if __name__ == "__main__":
    run("valoris-flow-router", main)
