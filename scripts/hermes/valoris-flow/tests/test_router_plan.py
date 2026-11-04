import unittest

from tests.helpers import HERE  # noqa: F401  (puts scripts/ on sys.path)

from valoris_flow_router import plan


def issue(n, *labels, title=None):
    return {"number": n, "title": title or f"bug {n}", "labels": ["triaged", *labels]}


def pr(n, closes, sha="s1", *labels, rejection=None):
    return {"number": n, "title": f"fix {closes}", "head_sha": sha, "closes": closes,
            "labels": ["auto-pr", *labels], "rejection_text": rejection}


def card(key, status="done", task_id=None):
    return {"key": key, "status": status, "id": task_id or f"t_{key.replace(':', '_')}"}


def cards_of(actions, stage):
    return [a for a in actions if a[0] == "card" and a[1] == stage]


class FixRuleTest(unittest.TestCase):
    def test_creates_fix_cards_lowest_first_up_to_cap(self):
        actions = plan([issue(66), issue(57), issue(59)], [], [])
        keys = [a[4] for a in cards_of(actions, "fix")]
        self.assertEqual(keys, ["valoris-flow:fix:57", "valoris-flow:fix:59"])
        self.assertEqual(actions[0][2], "#57 Corrigir: bug 57")

    def test_running_fix_cards_occupy_slots(self):
        cards = [card("valoris-flow:fix:57", "running"), card("valoris-flow:fix:59", "todo")]
        self.assertEqual(plan([issue(57), issue(59), issue(66)], [], cards), [])

    def test_open_prs_occupy_slots(self):
        prs = [pr(80, 57), pr(81, 59)]
        cards = [card("valoris-flow:fix:57"), card("valoris-flow:fix:59"),
                 card("valoris-flow:review:80:s1", "running"), card("valoris-flow:review:81:s1", "running")]
        self.assertEqual(cards_of(plan([issue(57), issue(59), issue(66)], prs, cards), "fix"), [])

    def test_skips_needs_human_issue_with_pr_or_existing_card(self):
        cards = [card("valoris-flow:fix:2")]
        prs = [pr(90, 3)]
        actions = plan([issue(1, "needs-human"), issue(2), issue(3)], prs, cards + [card("valoris-flow:fix:3")])
        self.assertEqual(cards_of(actions, "fix"), [])


class ReviewRuleTest(unittest.TestCase):
    def test_review_after_fix_card_done(self):
        actions = plan([issue(57)], [pr(80, 57)], [card("valoris-flow:fix:57", task_id="t_fix")])
        (review,) = cards_of(actions, "review")
        self.assertEqual(review[4], "valoris-flow:review:80:s1")
        self.assertEqual(review[2], "Revisar PR 80 (issue #57)")
        self.assertIn("Cycle: 1/3", review[3])
        self.assertEqual(review[5], ["t_fix"])

    def test_no_review_while_fix_card_still_running(self):
        actions = plan([issue(57)], [pr(80, 57)], [card("valoris-flow:fix:57", "running")])
        self.assertEqual(actions, [])

    def test_new_sha_gets_new_review_even_with_stale_ok_label(self):
        cards = [card("valoris-flow:fix:57"), card("valoris-flow:review:80:s1"), card("valoris-flow:qa:80:s1"),
                 card("valoris-flow:redo:80:s1", task_id="t_redo")]
        actions = plan([issue(57)], [pr(80, 57, "s2", "auto-review-ok")], cards)
        (review,) = cards_of(actions, "review")
        self.assertEqual(review[4], "valoris-flow:review:80:s2")
        self.assertIn("Cycle: 2/3", review[3])
        self.assertEqual(review[5], ["t_redo"])
        self.assertEqual(cards_of(actions, "qa"), [])

    def test_last_cycle_body_mentions_needs_human(self):
        cards = [card("valoris-flow:review:80:s1"), card("valoris-flow:review:80:s2")]
        (review,) = cards_of(plan([issue(57)], [pr(80, 57, "s3")], cards), "review")
        self.assertIn("Cycle: 3/3", review[3])
        self.assertIn("needs-human", review[3])


class QaRuleTest(unittest.TestCase):
    def test_qa_after_review_ok_on_head_sha(self):
        cards = [card("valoris-flow:fix:57"), card("valoris-flow:review:80:s1", task_id="t_rev")]
        (qa,) = cards_of(plan([issue(57)], [pr(80, 57, "s1", "auto-review-ok")], cards), "qa")
        self.assertEqual(qa[4], "valoris-flow:qa:80:s1")
        self.assertEqual(qa[2], "Testar PR 80 (issue #57)")
        self.assertEqual(qa[5], ["t_rev"])

    def test_nothing_after_qa_passed(self):
        cards = [card("valoris-flow:review:80:s1"), card("valoris-flow:qa:80:s1")]
        self.assertEqual(plan([issue(57)], [pr(80, 57, "s1", "auto-review-ok", "auto-qa-passed")], cards), [])


class RedoRuleTest(unittest.TestCase):
    def test_redo_after_changes_requested(self):
        cards = [card("valoris-flow:fix:57"), card("valoris-flow:review:80:s1", task_id="t_rev")]
        prs = [pr(80, 57, "s1", "auto-review-changes", rejection="**Review (keldorn): CHANGES REQUESTED**\nfix x")]
        (redo,) = cards_of(plan([issue(57)], prs, cards), "redo")
        self.assertEqual(redo[4], "valoris-flow:redo:80:s1")
        self.assertEqual(redo[2], "REDO #80 ciclo 2: bug 57")
        self.assertIn("fix x", redo[3])
        self.assertIn("https://github.com/josevictorferreira/valoris/pull/80", redo[3])
        self.assertEqual(redo[5], ["t_rev"])

    def test_redo_after_qa_failed_waits_for_qa_card(self):
        prs = [pr(80, 57, "s1", "auto-review-ok", "auto-qa-failed", rejection="**Test (jaheira): FAILED**")]
        running = [card("valoris-flow:review:80:s1"), card("valoris-flow:qa:80:s1", "running")]
        self.assertEqual(cards_of(plan([issue(57)], prs, running), "redo"), [])
        done = [card("valoris-flow:review:80:s1"), card("valoris-flow:qa:80:s1", task_id="t_qa")]
        (redo,) = cards_of(plan([issue(57)], prs, done), "redo")
        self.assertEqual(redo[5], ["t_qa"])

    def test_cycle_cap_labels_needs_human_and_posts_feed(self):
        cards = [card(f"valoris-flow:review:80:s{i}") for i in (1, 2, 3)]
        prs = [pr(80, 57, "s3", "auto-review-changes")]
        actions = plan([issue(57)], prs, cards)
        self.assertEqual(cards_of(actions, "redo"), [])
        self.assertIn(("label", 57, "needs-human"), actions)
        (feed,) = [a for a in actions if a[0] == "feed"]
        self.assertEqual(feed[1], "irenicus")
        self.assertIn("#57", feed[2])
        self.assertEqual(feed[3], "vf-cap-80-s3")

    def test_needs_human_issue_stops_everything_for_its_pr(self):
        cards = [card(f"valoris-flow:review:80:s{i}") for i in (1, 2, 3)]
        prs = [pr(80, 57, "s4", "auto-review-changes")]
        self.assertEqual(plan([issue(57, "needs-human")], prs, cards), [])


if __name__ == "__main__":
    unittest.main()
