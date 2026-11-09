import io
import sqlite3
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

from tests.helpers import FakeHTTP, add_comment, add_run, add_task, make_board

import valoris_flow as vf
import valoris_flow_router as router

API = "https://api.github.com/repos/josevictorferreira/valoris"


class LoadGitHubTest(unittest.TestCase):
    def test_builds_issue_and_pr_shapes(self):
        http = FakeHTTP({
            f"GET {API}/issues?state=open&labels=triaged": [
                {"number": 57, "title": "bug", "labels": [{"name": "triaged"}]},
                {"number": 99, "title": "a pr", "labels": [], "pull_request": {}},
            ],
            f"GET {API}/pulls?state=open": [
                {"number": 80, "title": "fix", "body": "x\n\nCloses #57", "head": {"sha": "s1"},
                 "labels": [{"name": "auto-pr"}, {"name": "auto-review-changes"}]},
                {"number": 81, "title": "human", "body": "", "head": {"sha": "h"}, "labels": []},
            ],
            f"GET {API}/issues/80/comments": [
                {"created_at": "2026-11-01T00:00:00Z", "body": "**Review (keldorn): CHANGES REQUESTED**\nold"},
                {"created_at": "2026-11-03T00:00:00Z", "body": "unrelated"},
            ],
            f"GET {API}/pulls/80/reviews": [
                {"submitted_at": "2026-11-02T00:00:00Z", "body": "**Review (keldorn): CHANGES REQUESTED**\nnew"},
            ],
        })
        with mock.patch.object(vf, "github_token", return_value="t"), mock.patch("urllib.request.urlopen", http):
            issues, prs = router.load_github()
        self.assertEqual(issues, [{"number": 57, "title": "bug", "labels": ["triaged"]}])
        self.assertEqual(len(prs), 1)
        self.assertEqual(prs[0]["closes"], 57)
        self.assertEqual(prs[0]["head_sha"], "s1")
        self.assertTrue(prs[0]["rejection_text"].endswith("new"))


class ApplyTest(unittest.TestCase):
    def test_dry_run_does_nothing(self):
        actions = [("card", "fix", "t", "b", "valoris-flow:fix:1", []), ("label", 1, "needs-human"),
                   ("feed", "irenicus", "x", "txn")]
        with mock.patch("subprocess.run") as run, mock.patch("urllib.request.urlopen") as urlopen, \
                redirect_stdout(io.StringIO()) as out:
            router.apply(actions, dry_run=True)
        run.assert_not_called()
        urlopen.assert_not_called()
        self.assertIn("card fix valoris-flow:fix:1", out.getvalue())

    def test_label_action_posts_label(self):
        http = FakeHTTP()
        with mock.patch.object(vf, "github_token", return_value="t"), mock.patch("urllib.request.urlopen", http):
            router.apply([("label", 57, "needs-human")], dry_run=False)
        self.assertEqual(http.calls[0]["url"], f"{API}/issues/57/labels")
        self.assertEqual(http.calls[0]["body"], {"labels": ["needs-human"]})


class BoardTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = make_board(tmp.name)
        self.db = sqlite3.connect(self.path)
        self.addCleanup(self.db.close)

    def test_load_cards_skips_archived_and_foreign(self):
        add_task(self.path, "t_a", "done", key="valoris-flow:fix:1", created_at=1)
        add_task(self.path, "t_b", "archived", key="valoris-flow:fix:2", created_at=2)
        add_task(self.path, "t_c", "todo", key="other:1", created_at=3)
        self.assertEqual(router.load_cards(self.db), [{"key": "valoris-flow:fix:1", "status": "done", "id": "t_a"}])

    def _mark_comment(self, task_id, text):
        add_comment(self.path, task_id, text)

    def test_feed_posted_once_and_only_inside_window(self):
        now = 10_000
        add_task(self.path, "t_new", "done", assignee="valygar")
        add_task(self.path, "t_old", "done", assignee="valygar")
        run_new = add_run(self.path, "t_new", now - 60, {"feed": "Criei o PR #80."})
        add_run(self.path, "t_old", now - router.FEED_WINDOW - 60, {"feed": "velho"})
        with mock.patch.object(router, "post_feed") as post, \
                mock.patch.object(router, "comment_card", side_effect=self._mark_comment):
            router.relay_feed(self.db, dry_run=False, now=now)
            router.relay_feed(self.db, dry_run=False, now=now)
        post.assert_called_once_with("valygar", "Criei o PR #80.", f"vf-done-{run_new}")

    def test_feed_ignores_cards_not_created_by_the_flow(self):
        add_task(self.path, "t_x", "done", created_by="user")
        add_run(self.path, "t_x", 9_990, {"feed": "x"})
        with mock.patch.object(router, "post_feed") as post:
            router.relay_feed(self.db, dry_run=False, now=10_000)
        post.assert_not_called()

    def test_blocked_announced_once(self):
        add_task(self.path, "t_b", "blocked", assignee="jaheira", title="Testar PR 80",
                 last_failure_error="CI red\nmore")
        with mock.patch.object(router, "post_feed") as post, \
                mock.patch.object(router, "comment_card", side_effect=self._mark_comment):
            router.announce_blocked(self.db, dry_run=False)
            router.announce_blocked(self.db, dry_run=False)
        post.assert_called_once_with("jaheira", "Travei no card t_b (Testar PR 80): CI red", "vf-blocked-t_b")


class DbRetryTest(unittest.TestCase):
    def test_retries_transient_operational_error(self):
        calls = []

        def flaky():
            calls.append(1)
            if len(calls) == 1:
                raise sqlite3.OperationalError("attempt to write a readonly database")
            return "ok"

        self.assertEqual(router.with_db_retry(flaky, wait=0), "ok")
        self.assertEqual(len(calls), 2)

    def test_gives_up_after_attempts(self):
        def broken():
            raise sqlite3.OperationalError("no such table")

        with self.assertRaises(sqlite3.OperationalError):
            router.with_db_retry(broken, attempts=2, wait=0)


if __name__ == "__main__":
    unittest.main()


class HealCardsTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = make_board(tmp.name)
        self.db = sqlite3.connect(self.path)
        self.addCleanup(self.db.close)

    def _mark_comment(self, task_id, text):
        add_comment(self.path, task_id, text)

    def test_reclaims_zombie_running_card_once_per_heartbeat(self):
        now = 10_000
        add_task(self.path, "t_z", "running", assignee="valygar", key="valoris-flow:fix:59")
        self.db.execute("update tasks set last_heartbeat_at = ?", (now - 2 * router.HEAL_STALE_HEARTBEAT,))
        self.db.commit()
        with mock.patch.object(router, "reclaim_card") as reclaim, \
                mock.patch.object(router, "post_feed") as post, \
                mock.patch.object(router, "comment_card", side_effect=self._mark_comment):
            first = router.heal_cards(self.db, dry_run=False, now=now)
            second = router.heal_cards(self.db, dry_run=False, now=now)
        self.assertEqual(first, ["t_z"])
        self.assertEqual(second, [])  # the heartbeat mark stops a re-reclaim
        reclaim.assert_called_once_with("t_z")
        post.assert_called_once()

    def test_fresh_running_card_left_alone(self):
        add_task(self.path, "t_ok", "running", assignee="valygar")
        self.db.execute("update tasks set last_heartbeat_at = 9_500", )
        self.db.commit()
        with mock.patch.object(router, "reclaim_card") as reclaim:
            self.assertEqual(router.heal_cards(self.db, dry_run=False, now=10_000), [])
        reclaim.assert_not_called()

    def test_running_without_heartbeat_is_left_alone(self):
        # None heartbeat means never started by this scheme; not a zombie we can judge
        add_task(self.path, "t_nb", "running", assignee="valygar")
        with mock.patch.object(router, "reclaim_card") as reclaim:
            self.assertEqual(router.heal_cards(self.db, dry_run=False, now=10_000), [])
        reclaim.assert_not_called()

    def test_unblocks_infra_blocked_card_bounded_times(self):
        add_task(self.path, "t_i", "blocked", assignee="valygar",
                 last_failure_error="Kanban owner refused: Kanban owner silent for 199s: TimeoutError")
        unblock = mock.patch.object(router, "unblock_card")
        with mock.patch.object(router, "post_feed") as post, \
                mock.patch.object(router, "comment_card", side_effect=self._mark_comment), \
                unblock as unblock_mock:
            healed = router.heal_cards(self.db, dry_run=False, now=10_000)
            # simulate hermes re-blocking for the same infra reason
            self.db.execute("update tasks set status = 'blocked'")
            self.db.commit()
            router.heal_cards(self.db, dry_run=False, now=10_000)
            self.db.execute("update tasks set status = 'blocked'")
            self.db.commit()
            third = router.heal_cards(self.db, dry_run=False, now=10_000)
        self.assertEqual(healed, ["t_i"])
        self.assertEqual(third, [])  # bounded at HEAL_BLOCK_RETRIES unblocks
        self.assertEqual(unblock_mock.call_count, router.HEAL_BLOCK_RETRIES)
        self.assertEqual(post.call_count, router.HEAL_BLOCK_RETRIES)

    def test_work_blocked_card_left_alone(self):
        add_task(self.path, "t_w", "blocked", assignee="keldorn",
                 last_failure_error="CI red: specs fail")
        with mock.patch.object(router, "unblock_card") as unblock:
            self.assertEqual(router.heal_cards(self.db, dry_run=False, now=10_000), [])
        unblock.assert_not_called()

    def test_heal_skips_cards_not_created_by_the_flow(self):
        add_task(self.path, "t_u", "running", assignee="valygar", created_by="user")
        self.db.execute("update tasks set last_heartbeat_at = 1")
        self.db.commit()
        with mock.patch.object(router, "reclaim_card") as reclaim:
            self.assertEqual(router.heal_cards(self.db, dry_run=False, now=10_000), [])
        reclaim.assert_not_called()

    def test_dry_run_prints_and_touches_nothing(self):
        import io
        from contextlib import redirect_stdout
        add_task(self.path, "t_d", "running", assignee="valygar", key="valoris-flow:fix:1")
        self.db.execute("update tasks set last_heartbeat_at = 1")
        self.db.commit()
        with mock.patch.object(router, "reclaim_card") as reclaim, \
                mock.patch.object(router, "post_feed"), \
                mock.patch.object(router, "comment_card"), \
                redirect_stdout(io.StringIO()) as out:
            self.assertEqual(router.heal_cards(self.db, dry_run=True, now=10_000), ["t_d"])
        self.assertIn("reclaim t_d", out.getvalue())
        reclaim.assert_not_called()
