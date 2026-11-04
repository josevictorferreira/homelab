#!/usr/bin/env python3
"""Valoris issue triage (no-agent cron, 06:00): one daily triage card for irenicus. Prints nothing."""
from datetime import date

from valoris_flow import REPO, create_card, locked_state, run


def main():
    today = date.today().isoformat()
    with locked_state() as state:
        active = sorted(int(n) for n, c in state["chains"].items() if c.get("active"))
        body = "\n".join([
            f"Triage the open issues of https://github.com/{REPO} that are not labeled `triaged`.",
            "Issues already being worked on by the flow (skip them): "
            + (", ".join(f"#{n}" for n in active) or "none"),
        ])
        create_card(state, "issues", f"Triagem de issues do Valoris {today}", body,
                    f"valoris-flow:issues:{today}")


if __name__ == "__main__":
    run("valoris-issues-triage", main)
