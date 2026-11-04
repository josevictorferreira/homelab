#!/usr/bin/env python3
"""Valoris issue triage (no-agent cron, 06:00): one daily triage card for irenicus. Prints nothing."""
from datetime import date

from valoris_flow import REPO, create_card, run


def main():
    today = date.today().isoformat()
    body = "\n".join([
        f"Triage the open issues of https://github.com/{REPO} that are not labeled `triaged`.",
        "Skip any issue that already has an open PR (`gh pr list --search \"<N> in:body\"`).",
    ])
    create_card("issues", f"Triagem de issues do Valoris {today}", body, f"valoris-flow:issues:{today}")


if __name__ == "__main__":
    run("valoris-issues-triage", main)
