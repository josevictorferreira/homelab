"""Shared helpers for the Valoris auto-fix flow (cron scripts owned by irenicus).

Flow: logs triage (jaheira, 05:00) -> GitHub issues -> issue triage (irenicus, 06:00)
-> fix (valygar) -> review (irenicus) -> test + merge (jaheira). Rejections create a
"REDO #<old card>" fix card. valoris_flow_router.py moves cards between stages and
posts each card's `metadata.feed` line to the Matrix feed room as that agent's user.
"""
import fcntl
import json
import os
import sqlite3
import subprocess
import urllib.parse
import urllib.request
import uuid
from contextlib import contextmanager

HERMES_ROOT = "/opt/data"
BOARD = "valoris"
BOARD_DB = f"{HERMES_ROOT}/kanban/boards/{BOARD}/kanban.db"
STATE_DIR = f"{HERMES_ROOT}/profiles/irenicus/valoris-flow"
STATE_PATH = f"{STATE_DIR}/state.json"
REPO = "josevictorferreira/valoris"
MAX_CYCLES = 3

MATRIX_HOMESERVER = "http://tuwunel.apps.svc.cluster.local:8008"
FEED_ROOM = "!BT1mrX0NFTmrzjW3Kp:josevictor.me"

# Stage -> (assignee profile, skill loaded into the worker)
STAGES = {
    "logs": ("jaheira", "valoris-log-triage"),
    "issues": ("irenicus", "valoris-issue-triage"),
    "fix": ("valygar", "valoris-fix"),
    "review": ("irenicus", "valoris-pr-review"),
    "test": ("jaheira", "valoris-pr-test"),
}


@contextmanager
def locked_state():
    """Load the flow state under an exclusive lock; always save it, so progress made
    before a failure is kept (card creation and feed posts are idempotent on retry)."""
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(f"{STATE_DIR}/.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(STATE_PATH) as f:
                state = json.load(f)
        except FileNotFoundError:
            state = {"cursor": None, "cards": {}, "chains": {}}
        try:
            yield state
        finally:
            _save(state)


def _save(state):
    tmp = f"{STATE_PATH}.tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2, sort_keys=True)
    os.replace(tmp, STATE_PATH)


def create_card(state, stage, title, body, idempotency_key, parents=(), **info):
    """Create a kanban card for `stage` and remember it in the flow state."""
    assignee, skill = STAGES[stage]
    cmd = ["hermes", "kanban", "--board", BOARD, "create", title,
           "--assignee", assignee, "--skill", skill, "--body-file", "-",
           "--idempotency-key", idempotency_key, "--created-by", "valoris-flow", "--json"]
    for parent in parents:
        cmd += ["--parent", parent]
    out = subprocess.run(cmd, input=body, capture_output=True, text=True, check=True).stdout
    task_id = json.loads(out)["id"]
    state["cards"][task_id] = {"stage": stage, **info}
    return task_id


def board():
    return sqlite3.connect(f"file:{BOARD_DB}?mode=ro", uri=True, timeout=30)


def _feed_token(profile):
    with open(f"{HERMES_ROOT}/profiles/{profile}/.env") as f:
        for line in f:
            if line.startswith("FEED_MATRIX_TOKEN="):
                return line.split("=", 1)[1].strip()
    raise RuntimeError(f"FEED_MATRIX_TOKEN missing in profiles/{profile}/.env")


def post_feed(profile, text, txn_id=None):
    """Post one message to the feed room as `profile`'s own Matrix user.

    A stable txn_id makes a retried post idempotent on the homeserver side.
    """
    txn = urllib.parse.quote(txn_id or uuid.uuid4().hex)
    room = urllib.parse.quote(FEED_ROOM)
    req = urllib.request.Request(
        f"{MATRIX_HOMESERVER}/_matrix/client/v3/rooms/{room}/send/m.room.message/{txn}",
        method="PUT", data=json.dumps({"msgtype": "m.text", "body": text}).encode(),
        headers={"Authorization": f"Bearer {_feed_token(profile)}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30):
        pass


def run(job_name, main):
    """Run a cron entrypoint; on failure post one feed warning per distinct error, then re-raise.

    These jobs deliver to `local`, so without this a broken step would stall the flow silently.
    """
    marker = f"{STATE_DIR}/{job_name}.last-error"
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
            os.makedirs(STATE_DIR, exist_ok=True)
            with open(marker, "w") as f:
                f.write(error)
            post_feed("irenicus", f"⚠️ O job {job_name} falhou: {error}")
        raise
    else:
        if os.path.exists(marker):
            os.remove(marker)
