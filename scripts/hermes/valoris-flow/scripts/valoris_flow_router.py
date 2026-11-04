#!/usr/bin/env python3
"""Valoris flow router (no-agent cron, every 5 min). Stateless: every tick it

  1. reads open `triaged` issues and open `auto-pr` PRs from GitHub plus the flow cards on the
     kanban board, and creates whatever card the label state calls for (plan() below; the
     idempotency key of each card makes re-creation a no-op);
  2. relays each completed flow card's `metadata.feed` line to the Matrix feed room;
  3. announces, once, every flow card that ends up blocked.

`--dry-run` prints the actions instead of performing them. Otherwise prints nothing.
"""
import json
import re
import sqlite3
import sys
import time

from valoris_flow import (MAX_CYCLES, MAX_OPEN_FIXES, REPO, board, closes_issue, comment_card, create_card, gh,
                          gh_paged, post_feed, run)

PREFIX = "valoris-flow:"
REJECTIONS = ("auto-review-changes", "auto-qa-failed")
REJECTION_HEADER = re.compile(r"^\s*\*\*(Review \(\w+\): CHANGES REQUESTED|Test \(\w+\): FAILED)\*\*")
FEED_WINDOW = 2 * 3600
FEED_MARK = "vf:feed-posted:"
BLOCKED_MARK = "vf:blocked-announced"


def issue_url(n):
    return f"https://github.com/{REPO}/issues/{n}"


def pr_url(n):
    return f"https://github.com/{REPO}/pull/{n}"


# ---------------------------------------------------------------- planning (pure)

def plan(issues, prs, cards):
    """Return the actions this tick needs. No I/O.

    issues: open issues labeled `triaged`: {number, title, labels}
    prs:    open PRs labeled `auto-pr`:   {number, title, head_sha, labels, closes, rejection_text}
    cards:  non-archived flow cards in creation order: {key, status, id}
    Actions: ("card", stage, title, body, key, parents) | ("label", issue, label) | ("feed", profile, text, txn)
    """
    by_key = {c["key"]: c for c in cards}
    issue_by_n = {i["number"]: i for i in issues}
    actions = []

    def done(key):
        return by_key.get(key, {}).get("status") == "done"

    def active(key):
        return key in by_key and by_key[key]["status"] != "done"

    def keys(prefix):
        return [c for c in cards if c["key"].startswith(prefix)]

    for p in prs:
        n, sha, labels = p["number"], p["head_sha"], set(p["labels"])
        issue = issue_by_n.get(p["closes"])
        if "needs-human" in labels or (issue and "needs-human" in issue["labels"]):
            continue
        title = issue["title"] if issue else p["title"]
        redos = keys(f"{PREFIX}redo:{n}:")
        if (p["closes"] and active(f"{PREFIX}fix:{p['closes']}")) or any(c["status"] != "done" for c in redos):
            continue  # valygar is still pushing to this PR
        reviews = keys(f"{PREFIX}review:{n}:")
        review_key, qa_key = f"{PREFIX}review:{n}:{sha}", f"{PREFIX}qa:{n}:{sha}"
        ref = {"issue": p["closes"], "title": title, "pr": n}

        if review_key not in by_key:
            last = redos[-1] if redos else by_key.get(f"{PREFIX}fix:{p['closes']}")
            actions.append(("card", "review", f"Revisar PR {n} (issue #{p['closes']})",
                            stage_body(ref, len(reviews) + 1), review_key, [last["id"]] if last else []))
            continue
        if not done(review_key):
            continue

        rejected_by = None
        if "auto-qa-failed" in labels and done(qa_key):
            rejected_by = by_key[qa_key]
        elif "auto-review-changes" in labels and "auto-qa-failed" not in labels:
            rejected_by = by_key[review_key]
        if rejected_by:
            redo_key = f"{PREFIX}redo:{n}:{sha}"
            if redo_key in by_key:
                continue
            if len(reviews) >= MAX_CYCLES:
                if p["closes"]:
                    actions.append(("label", p["closes"], "needs-human"))
                actions.append(("feed", "irenicus",
                                f"A issue #{p['closes']} foi recusada {MAX_CYCLES} vezes e precisa de você: {pr_url(n)}",
                                f"vf-cap-{n}-{sha}"))
                continue
            actions.append(("card", "redo", f"REDO #{n} ciclo {len(reviews) + 1}: {title}",
                            redo_body(ref, len(reviews) + 1, p.get("rejection_text")), redo_key, [rejected_by["id"]]))
            continue

        if "auto-review-ok" in labels and not labels & {"auto-qa-passed", "auto-qa-failed"} and qa_key not in by_key:
            actions.append(("card", "qa", f"Testar PR {n} (issue #{p['closes']})", stage_body(ref, len(reviews)),
                            qa_key, [by_key[review_key]["id"]]))

    occupied = {p["closes"] or f"pr{p['number']}" for p in prs}
    occupied |= {int(c["key"].rsplit(":", 1)[1]) for c in keys(f"{PREFIX}fix:") if c["status"] != "done"}
    slots = MAX_OPEN_FIXES - len(occupied)
    with_pr = {p["closes"] for p in prs}
    for i in sorted(issues, key=lambda i: i["number"]):
        if slots <= 0:
            break
        n = i["number"]
        if "needs-human" in i["labels"] or n in with_pr or f"{PREFIX}fix:{n}" in by_key:
            continue
        actions.append(("card", "fix", f"#{n} Corrigir: {i['title']}", fix_body(n, i["title"]), f"{PREFIX}fix:{n}", []))
        slots -= 1
    return actions


def fix_body(n, title):
    return "\n".join([f"Issue: {issue_url(n)} ({title})", f"Cycle: 1/{MAX_CYCLES}",
                      f"Open the PR with the label `auto-pr` and `Closes #{n}` in its body."])


def stage_body(ref, cycle):
    lines = [f"PR: {pr_url(ref['pr'])}", f"Issue: {issue_url(ref['issue'])} ({ref['title']})",
             f"Cycle: {cycle}/{MAX_CYCLES}"]
    if cycle >= MAX_CYCLES:
        lines.append(f"This is the last cycle: if you reject, also add the label `needs-human` to issue #{ref['issue']}.")
    return "\n".join(lines)


def redo_body(ref, cycle, rejection):
    return "\n".join([
        f"PR: {pr_url(ref['pr'])}", f"Issue: {issue_url(ref['issue'])} ({ref['title']})", f"Cycle: {cycle}/{MAX_CYCLES}",
        "REDO: the previous attempt was rejected. Address every finding below, push new commits to the PR's",
        "existing branch (do not open a new PR), then remove the verdict labels from the PR.",
        "", "Rejection:", (rejection or "(see the latest review/test comment on the PR)")[:6000]])


# ---------------------------------------------------------------- I/O

def _labels(item):
    return [label["name"] for label in item.get("labels", [])]


def latest_rejection(n):
    """Newest PR comment or review whose body starts with a rejection header."""
    found = [(c["created_at"], c["body"]) for c in gh_paged(f"/repos/{REPO}/issues/{n}/comments?per_page=100")]
    found += [(r.get("submitted_at") or "", r["body"]) for r in gh_paged(f"/repos/{REPO}/pulls/{n}/reviews?per_page=100")]
    matching = sorted((ts, body) for ts, body in found if body and REJECTION_HEADER.match(body))
    return matching[-1][1] if matching else None


def load_github():
    issues = [{"number": i["number"], "title": i["title"], "labels": _labels(i)}
              for i in gh_paged(f"/repos/{REPO}/issues?state=open&labels=triaged&per_page=100")
              if "pull_request" not in i]
    prs = []
    for p in gh_paged(f"/repos/{REPO}/pulls?state=open&per_page=100"):
        labels = _labels(p)
        if "auto-pr" not in labels:
            continue
        prs.append({"number": p["number"], "title": p["title"], "head_sha": p["head"]["sha"], "labels": labels,
                    "closes": closes_issue(p.get("body")),
                    "rejection_text": latest_rejection(p["number"]) if set(labels) & set(REJECTIONS) else None})
    return issues, prs


def load_cards(db):
    rows = db.execute("select idempotency_key, status, id from tasks where idempotency_key like ? "
                      "and status != 'archived' order by created_at, rowid", (PREFIX + "%",)).fetchall()
    return [{"key": k, "status": s, "id": i} for k, s, i in rows]


def apply(actions, dry_run):
    for action in actions:
        if dry_run:
            print(" ".join(str(part) for part in (action[:2] + action[4:5] if action[0] == "card" else action)))
            continue
        kind = action[0]
        if kind == "card":
            _, stage, title, body, key, parents = action
            create_card(stage, title, body, key, parents)
        elif kind == "label":
            gh("POST", f"/repos/{REPO}/issues/{action[1]}/labels", {"labels": [action[2]]})
        elif kind == "feed":
            post_feed(action[1], action[2], action[3])


def _commented(db, task_id, body):
    return db.execute("select 1 from task_comments where task_id = ? and body = ?", (task_id, body)).fetchone()


def relay_feed(db, dry_run, now=None):
    since = (now or time.time()) - FEED_WINDOW
    rows = db.execute("select r.id, r.task_id, t.assignee, r.metadata from task_runs r join tasks t on t.id = r.task_id "
                      "where r.outcome = 'completed' and r.ended_at > ? and t.created_by = 'valoris-flow' "
                      "order by r.id", (since,)).fetchall()
    for run_id, task_id, assignee, metadata in rows:
        try:
            feed = (json.loads(metadata) if metadata else {}).get("feed")
        except ValueError:
            feed = None
        mark = f"{FEED_MARK}{run_id}"
        if not feed or _commented(db, task_id, mark):
            continue
        if dry_run:
            print(f"feed {assignee} {feed}")
            continue
        post_feed(assignee, feed, f"vf-done-{run_id}")
        comment_card(task_id, mark)


def announce_blocked(db, dry_run):
    rows = db.execute("select id, assignee, title, last_failure_error from tasks "
                      "where status = 'blocked' and created_by = 'valoris-flow'").fetchall()
    for task_id, assignee, title, error in rows:
        if _commented(db, task_id, BLOCKED_MARK):
            continue
        reason = (error or "sem motivo registrado").splitlines()[0][:200]
        if dry_run:
            print(f"blocked {task_id} {reason}")
            continue
        post_feed(assignee, f"Travei no card {task_id} ({title}): {reason}", f"vf-blocked-{task_id}")
        comment_card(task_id, BLOCKED_MARK)


def with_db_retry(fn, attempts=3, wait=3):
    """Board reads can fail for a moment while a writer holds a hot rollback journal on CephFS
    ("attempt to write a readonly database"); retry instead of reporting a blip as a broken job."""
    for attempt in range(attempts):
        try:
            return fn()
        except sqlite3.OperationalError:
            if attempt == attempts - 1:
                raise
            time.sleep(wait)


def main(argv=None):
    dry_run = "--dry-run" in (sys.argv[1:] if argv is None else argv)
    db = board()
    issues, prs = load_github()
    apply(plan(issues, prs, with_db_retry(lambda: load_cards(db))), dry_run)
    with_db_retry(lambda: relay_feed(db, dry_run))
    with_db_retry(lambda: announce_blocked(db, dry_run))


if __name__ == "__main__":
    if "--dry-run" in sys.argv:
        main()
    else:
        run("valoris-flow-router", main)
