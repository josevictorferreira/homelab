import json
import os
import subprocess
import tempfile
import unittest
from unittest import mock

from tests.helpers import FakeHTTP

import valoris_flow as vf


class ClosesIssueTest(unittest.TestCase):
    def test_keywords(self):
        self.assertEqual(vf.closes_issue("Root cause...\n\nCloses #53"), 53)
        self.assertEqual(vf.closes_issue("this fixes #7."), 7)
        self.assertEqual(vf.closes_issue("Fixed #8"), 8)
        self.assertEqual(vf.closes_issue("Resolves #9 and closes #10"), 9)

    def test_none(self):
        self.assertIsNone(vf.closes_issue("mentions #12 but closes nothing"))
        self.assertIsNone(vf.closes_issue(None))


class GitHubTest(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.object(vf, "github_token", return_value="tok")
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_headers_and_body(self):
        http = FakeHTTP({"POST https://api.github.com/repos/x/issues/1/labels": [{"name": "a"}]})
        with mock.patch("urllib.request.urlopen", http):
            out = vf.gh("POST", "/repos/x/issues/1/labels", {"labels": ["a"]})
        self.assertEqual(out, [{"name": "a"}])
        call = http.calls[0]
        self.assertEqual(call["headers"]["Authorization"], "Bearer tok")
        self.assertEqual(call["headers"]["Accept"], "application/vnd.github+json")
        self.assertEqual(call["body"], {"labels": ["a"]})

    def test_error_carries_response_body(self):
        http = FakeHTTP({"GET https://api.github.com/bad": (422, {"message": "Validation Failed"}, {})})
        with mock.patch("urllib.request.urlopen", http):
            with self.assertRaisesRegex(RuntimeError, "422.*Validation Failed"):
                vf.gh("GET", "/bad")

    def test_paged_follows_next_link(self):
        page2 = "https://api.github.com/repos/x/pulls?page=2"
        http = FakeHTTP({
            f"GET {page2}": [{"n": 2}],
            "GET https://api.github.com/repos/x/pulls": (200, [{"n": 1}], {"Link": f'<{page2}>; rel="next"'}),
        })
        with mock.patch("urllib.request.urlopen", http):
            self.assertEqual(vf.gh_paged("/repos/x/pulls"), [{"n": 1}, {"n": 2}])


class TokenTest(unittest.TestCase):
    def test_reads_profile_env_when_env_is_scrubbed(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(f"{tmp}/profiles/irenicus")
            with open(f"{tmp}/profiles/irenicus/.env", "w") as f:
                f.write("# comment\nGH_TOKEN='abc'\n")
            with mock.patch.object(vf, "HERMES_ROOT", tmp), mock.patch.dict(os.environ, {}, clear=True):
                self.assertEqual(vf.github_token(), "abc")


class CreateCardTest(unittest.TestCase):
    def test_passes_idempotency_key_and_returns_id(self):
        done = subprocess.CompletedProcess([], 0, stdout=json.dumps({"id": "t_1"}), stderr="")
        with mock.patch("subprocess.run", return_value=done) as run:
            task_id = vf.create_card("review", "Revisar PR 5", "body", "valoris-flow:review:5:abc", ["t_0"])
        self.assertEqual(task_id, "t_1")
        cmd = run.call_args.args[0]
        self.assertIn("--idempotency-key", cmd)
        self.assertEqual(cmd[cmd.index("--idempotency-key") + 1], "valoris-flow:review:5:abc")
        self.assertEqual(cmd[cmd.index("--assignee") + 1], "keldorn")
        self.assertEqual(cmd[cmd.index("--skill") + 1], "valoris-pr-review")
        self.assertEqual(cmd[cmd.index("--parent") + 1], "t_0")
        self.assertEqual(run.call_args.kwargs["input"], "body")


class FeedFallbackTest(unittest.TestCase):
    def test_profile_without_token_posts_as_irenicus_with_prefix(self):
        with tempfile.TemporaryDirectory() as tmp:
            for p, content in (("irenicus", "FEED_MATRIX_TOKEN=irt\n"), ("keldorn", "OTHER=1\n")):
                os.makedirs(f"{tmp}/profiles/{p}")
                with open(f"{tmp}/profiles/{p}/.env", "w") as f:
                    f.write(content)
            http = FakeHTTP()
            with mock.patch.object(vf, "HERMES_ROOT", tmp), mock.patch("urllib.request.urlopen", http):
                vf.post_feed("keldorn", "Revisei o PR #5.", "txn1")
        call = http.calls[0]
        self.assertEqual(call["method"], "PUT")
        self.assertTrue(call["url"].endswith("/send/m.room.message/txn1"))
        self.assertEqual(call["headers"]["Authorization"], "Bearer irt")
        self.assertEqual(call["body"]["body"], "[keldorn] Revisei o PR #5.")


if __name__ == "__main__":
    unittest.main()
