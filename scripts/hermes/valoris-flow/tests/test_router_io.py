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


if __name__ == "__main__":
    unittest.main()
