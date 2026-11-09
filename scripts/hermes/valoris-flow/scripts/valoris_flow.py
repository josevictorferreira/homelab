"""Shared helpers for the Valoris auto-fix flow (no-agent cron scripts owned by irenicus).

Flow: logs triage (jaheira, 05:00) -> GitHub issues -> issue triage (irenicus, 06:00, label `triaged`)
-> fix (valygar, PR labeled `auto-pr`) -> review (keldorn, `auto-review-ok|changes`)
-> QA (jaheira, `auto-qa-passed|failed`) -> José merges. Rejections create REDO fix cards.

There is no state file: GitHub labels plus the kanban board are the whole state, and
valoris_flow_router.py derives the next cards from them every tick (idempotency keys dedupe).
Source of truth: homelab repo scripts/hermes/valoris-flow/ (synced here by sync.sh).
"""
import json
import os
import re
import sqlite3
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import uuid

HERMES_ROOT = "/opt/data"
BOARD = "valoris"
REPO = "josevictorferreira/valoris"
GITHUB_API = "https://api.github.com"
MAX_CYCLES = 3
MAX_OPEN_FIXES = 2

MATRIX_HOMESERVER = "http://tuwunel.apps.svc.cluster.local:8008"
FEED_ROOM = "!BT1mrX0NFTmrzjW3Kp:josevictor.me"
FEED_FALLBACK_PROFILE = "irenicus"

# Stage -> (assignee profile, skill loaded into the worker)
STAGES = {
    "logs": ("jaheira", "valoris-log-triage"),
    "issues": ("irenicus", "valoris-issue-triage"),
    "fix": ("valygar", "valoris-fix"),
    "redo": ("valygar", "valoris-fix"),
    "review": ("keldorn", "valoris-pr-review"),
    "qa": ("jaheira", "valoris-pr-test"),
}

_CLOSES = re.compile(r"(?i)\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)")


def board_db_path():
    return f"{HERMES_ROOT}/kanban/boards/{BOARD}/kanban.db"


def board():
    return sqlite3.connect(f"file:{board_db_path()}?mode=ro", uri=True, timeout=30)


def create_card(stage, title, body, idempotency_key, parents=()):
    """Create a kanban card for `stage`; an existing non-archived card with the same key is returned instead."""
    assignee, skill = STAGES[stage]
    cmd = ["hermes", "kanban", "--board", BOARD, "create", title,
           "--assignee", assignee, "--skill", skill, "--body-file", "-",
           "--idempotency-key", idempotency_key, "--created-by", "valoris-flow", "--json"]
    for parent in parents:
        cmd += ["--parent", parent]
    out = subprocess.run(cmd, input=body, capture_output=True, text=True, check=True).stdout
    return json.loads(out)["id"]


def comment_card(task_id, text):
    subprocess.run(["hermes", "kanban", "--board", BOARD, "comment", task_id, text, "--author", "valoris-flow"],
                   capture_output=True, text=True, check=True)


def reclaim_card(task_id):
    """Release a running card's worker claim so the dispatcher re-spawns it (zombie sweep)."""
    subprocess.run(["hermes", "kanban", "--board", BOARD, "reclaim", task_id],
                   capture_output=True, text=True, check=True)


def unblock_card(task_id):
    """Return a blocked card to ready (resets the consecutive-failure breaker)."""
    subprocess.run(["hermes", "kanban", "--board", BOARD, "unblock", task_id],
                   capture_output=True, text=True, check=True)


def closes_issue(pr_body):
    """The issue number a PR body closes (`Closes #N`, `Fixes #N`, ...), or None."""
    m = _CLOSES.search(pr_body or "")
    return int(m.group(1)) if m else None


def _env_value(profile, keys):
    try:
        with open(f"{HERMES_ROOT}/profiles/{profile}/.env") as f:
            for line in f:
                key, sep, value = line.strip().partition("=")
                if sep and key in keys and value:
                    return value.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return None


def github_token():
    """Cron scripts run with secrets scrubbed from the environment, so fall back to irenicus' .env."""
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") \
        or _env_value("irenicus", ("GH_TOKEN", "GITHUB_TOKEN"))
    if not token:
        raise RuntimeError("no GH_TOKEN in the environment or profiles/irenicus/.env")
    return token


def _gh_request(method, path, body=None):
    url = path if path.startswith("https://") else f"{GITHUB_API}{path}"
    req = urllib.request.Request(
        url, method=method, data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {github_token()}", "Accept": "application/vnd.github+json",
                 "User-Agent": "valoris-flow", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return (json.loads(raw) if raw else None), r.headers.get("Link")
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"GitHub {method} {path}: HTTP {exc.code} {exc.read()[:300].decode(errors='replace')}") \
            from None


def gh(method, path, body=None):
    return _gh_request(method, path, body)[0]


def gh_paged(path, max_pages=10):
    items, url = [], path
    for _ in range(max_pages):
        page, link = _gh_request("GET", url)
        items += page
        m = re.search(r'<([^>]+)>;\s*rel="next"', link or "")
        if not m:
            break
        url = m.group(1)
    return items


def _feed_token(profile):
    return _env_value(profile, ("FEED_MATRIX_TOKEN",))


def post_feed(profile, text, txn_id=None):
    """Post one message to the feed room as `profile`'s own Matrix user.

    Profiles without a feed user post through irenicus with a `[profile]` prefix.
    A stable txn_id makes a retried post idempotent on the homeserver side.
    """
    token = _feed_token(profile)
    if not token:
        token = _feed_token(FEED_FALLBACK_PROFILE)
        text = f"[{profile}] {text}"
    if not token:
        raise RuntimeError(f"FEED_MATRIX_TOKEN missing in profiles/{profile}/.env and the fallback profile")
    txn = urllib.parse.quote(txn_id or uuid.uuid4().hex)
    room = urllib.parse.quote(FEED_ROOM)
    req = urllib.request.Request(
        f"{MATRIX_HOMESERVER}/_matrix/client/v3/rooms/{room}/send/m.room.message/{txn}",
        method="PUT", data=json.dumps({"msgtype": "m.text", "body": text}).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30):
        pass


def run(job_name, main):
    """Run a cron entrypoint; on failure post one feed warning per distinct error, then re-raise.

    These jobs deliver to `local`, so without this a broken step would stall the flow silently.
    """
    marker_dir = f"{HERMES_ROOT}/profiles/irenicus/valoris-flow"
    marker = f"{marker_dir}/{job_name}.last-error"
    try:
        main()
    except Exception as exc:
        error = f"{type(exc).__name__}: {exc}"[:300]
        try:
            with open(marker) as f:
                seen = f.read() == error
        except FileNotFoundError:
            seen = False
        if not seen:
            os.makedirs(marker_dir, exist_ok=True)
            with open(marker, "w") as f:
                f.write(error)
            post_feed("irenicus", f"⚠️ O job {job_name} falhou: {error}")
        raise
    else:
        if os.path.exists(marker):
            os.remove(marker)
