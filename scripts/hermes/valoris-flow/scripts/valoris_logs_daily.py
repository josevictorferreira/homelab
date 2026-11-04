#!/usr/bin/env python3
"""Valoris logs triage (no-agent cron, 05:00).

Collects the last 24h of Valoris errors from Loki, groups them by fingerprint and, if
there is anything, creates one kanban card for jaheira to turn the groups into GitHub
issues. Deterministic: the agent only runs when there are errors. Prints nothing.
"""
import hashlib
import json
import re
import time
import urllib.parse
import urllib.request
from datetime import date, datetime, timezone

from valoris_flow import create_card, locked_state, run

LOKI = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1"
WINDOW = 24 * 3600
MAX_GROUPS = 25
JOB_FAILURE = re.compile(r"Error performing (?P<job>\S+) \(Job ID: (?P<job_id>[0-9a-f-]+)\) "
                         r"from SolidQueue\((?P<queue>[^)]*)\) in [\d.]+ms: (?P<exc>[A-Z][\w:]*) \((?P<msg>.*)", re.S)


def loki(path, **params):
    url = f"{LOKI}/{path}?{urllib.parse.urlencode(params)}"
    with urllib.request.urlopen(url, timeout=120) as r:
        return json.load(r)["data"]["result"]


def lines(query, start, end, limit, direction="backward"):
    result = loki("query_range", query=query, start=int(start * 1e9), end=int(end * 1e9),
                  limit=limit, direction=direction)
    return sorted((int(ts), line) for stream in result for ts, line in stream["values"])


def normalize(text):
    text = re.sub(r"[0-9a-f]{8}-[0-9a-f-]{27}", "<uuid>", text)
    text = re.sub(r"(https?://[^/\s]+)\S*", r"\1/…", text)
    return re.sub(r"(?<!\w)\d+", "N", text).strip()[:300]


def iso(ns):
    return datetime.fromtimestamp(ns / 1e9, timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")


def job_failure_groups(start, end):
    """One group per (job class, exception class, first app frame)."""
    counts = loki("query", time=int(end), query=(
        'sum by (job_class, exc) (count_over_time({app="valoris-worker"} |= "Error performing" '
        '| regexp "Error performing (?P<job_class>\\\\S+) .*?ms: (?P<exc>[A-Z][\\\\w:]*) " [24h]))'))
    groups = []
    for series in counts:
        job, exc = series["metric"].get("job_class"), series["metric"].get("exc")
        if not job or not exc:
            continue
        needle = f'{{app="valoris-worker"}} |= "Error performing {job} " |= "ms: {exc} ("'
        latest = lines(needle, start, end, 1)
        first = lines(needle, start, end, 1, "forward")
        if not latest:
            continue
        ts, line = latest[-1]
        m = JOB_FAILURE.search(line)
        # The backtrace follows the failure line as separate "app/..." log lines.
        after = lines('{app="valoris-worker"}', ts / 1e9, ts / 1e9 + 2, 40, "forward")
        frames = [l.strip() for _, l in after if l.strip().startswith("app/")][:12]
        args = []
        if m:
            args = lines(f'{{app="valoris-worker"}} |= "{m["job_id"]}" |= "Performing"', ts / 1e9 - 3600, ts / 1e9, 1)
        top = re.sub(r":\d+:", ":", frames[0]) if frames else ""
        groups.append({
            "kind": "job_failure", "count": int(series["value"][1]),
            "fingerprint": hashlib.sha1(f"{job}|{exc}|{top}".encode()).hexdigest()[:12],
            "job_class": job, "exception": exc, "queue": m["queue"] if m else None,
            "message": normalize(m["msg"]) if m else normalize(line),
            "first_seen": iso(first[0][0]) if first else iso(ts), "last_seen": iso(ts),
            "backtrace": frames, "example_arguments": args[-1][1][:600] if args else None,
        })
    return groups


def message_groups(query, kind, start, end, limit=2000):
    """Other error lines (fatal, backend errors, logged-but-handled errors) by normalized text."""
    groups = {}
    for ts, line in lines(query, start, end, limit):
        key = normalize(line)
        g = groups.setdefault(key, {"kind": kind, "count": 0, "message": key, "first_seen": iso(ts),
                                    "fingerprint": hashlib.sha1(f"{kind}|{key}".encode()).hexdigest()[:12],
                                    "example": line.strip()[:600]})
        g["count"] += 1
        g["last_seen"] = iso(ts)
    return list(groups.values())


def render(groups, start, end):
    out = [f"Valoris errors from Loki, {iso(start * 1e9)} → {iso(end * 1e9)}.",
           f"{len(groups)} distinct groups (counts are exact for job failures, sampled for other lines).", ""]
    for i, g in enumerate(groups, 1):
        title = f"{g['exception']} in {g['job_class']}" if g["kind"] == "job_failure" else g["message"][:120]
        out += [f"## {i}. [{g['kind']}] {title}",
                f"- fingerprint: `{g['fingerprint']}`", f"- occurrences: {g['count']}",
                f"- first seen: {g['first_seen']} / last seen: {g['last_seen']}"]
        if g["kind"] == "job_failure":
            out += [f"- queue: {g['queue']}", f"- message: {g['message']}"]
            if g["backtrace"]:
                out += ["- backtrace:", "```", *g["backtrace"], "```"]
            if g["example_arguments"]:
                out += ["- example job log line:", "```", g["example_arguments"], "```"]
        else:
            out += ["- example:", "```", g["example"], "```"]
        out.append("")
    return "\n".join(out)


def main():
    end = time.time()
    start = end - WINDOW
    groups = job_failure_groups(start, end)
    groups += message_groups('{app="valoris-worker", detected_level=~"error|fatal"} != "Error performing" '
                             '!= "Error in thread"', "worker_error", start, end)
    groups += message_groups('{app="valoris-backend"} |~ "Completed 5\\\\d\\\\d|Error|Exception|FATAL"',
                             "backend_error", start, end)
    if not groups:
        return
    groups = sorted(groups, key=lambda g: -g["count"])[:MAX_GROUPS]
    today = date.today().isoformat()
    with locked_state() as state:
        create_card(state, "logs", f"Triagem de logs do Valoris {today}", render(groups, start, end),
                    f"valoris-flow:logs:{today}")


if __name__ == "__main__":
    run("valoris-logs-triage", main)
