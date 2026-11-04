"""Test helpers: a temp kanban board with the real schema and a fake urlopen."""
import io
import json
import os
import sqlite3
import sys
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "scripts"))


def make_board(tmpdir):
    path = os.path.join(tmpdir, "kanban.db")
    with open(os.path.join(HERE, "kanban_schema.sql")) as f:
        sqlite3.connect(path).executescript(f.read())
    return path


def add_task(path, task_id, status="todo", assignee="valygar", key=None, created_by="valoris-flow",
             title="t", created_at=1, last_failure_error=None):
    with sqlite3.connect(path) as db:
        db.execute("insert into tasks (id, title, assignee, status, created_by, created_at, idempotency_key,"
                   " last_failure_error) values (?, ?, ?, ?, ?, ?, ?, ?)",
                   (task_id, title, assignee, status, created_by, created_at, key, last_failure_error))


def add_run(path, task_id, ended_at, metadata=None, outcome="completed", profile="valygar", summary=None):
    with sqlite3.connect(path) as db:
        cur = db.execute("insert into task_runs (task_id, profile, status, started_at, ended_at, outcome, summary,"
                         " metadata) values (?, ?, 'done', ?, ?, ?, ?, ?)",
                         (task_id, profile, ended_at - 10, ended_at, outcome, summary,
                          json.dumps(metadata) if metadata is not None else None))
        return cur.lastrowid


def add_comment(path, task_id, body, author="valoris-flow"):
    with sqlite3.connect(path) as db:
        db.execute("insert into task_comments (task_id, author, body, created_at) values (?, ?, ?, 1)",
                   (task_id, author, body))


class FakeResponse(io.BytesIO):
    def __init__(self, body, headers=None):
        super().__init__(body)
        self.headers = headers or {}

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class FakeHTTP:
    """Replaces urllib.request.urlopen. `routes` maps "METHOD url" (or a url prefix) to a response:
    a JSON-able object, or (status, object, headers). Records every request in `calls`."""

    def __init__(self, routes=None):
        self.routes = routes or {}
        self.calls = []

    def __call__(self, req, timeout=None):
        method = req.get_method()
        body = json.loads(req.data) if req.data else None
        self.calls.append({"method": method, "url": req.full_url, "body": body, "headers": dict(req.header_items())})
        resp = self.routes.get(f"{method} {req.full_url}")
        if resp is None:
            for key, value in self.routes.items():
                if key.startswith(f"{method} ") and req.full_url.startswith(key.split(" ", 1)[1]):
                    resp = value
                    break
        if resp is None:
            resp = {}
        status, obj, headers = resp if isinstance(resp, tuple) else (200, resp, {})
        raw = json.dumps(obj).encode() if obj is not None else b""
        if status >= 400:
            raise urllib.error.HTTPError(req.full_url, status, "error", headers, io.BytesIO(raw))
        return FakeResponse(raw, headers)
