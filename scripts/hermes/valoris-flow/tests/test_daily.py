import unittest
from unittest import mock

from tests.helpers import HERE  # noqa: F401  (puts scripts/ on sys.path)

import valoris_issues_daily
import valoris_logs_daily


class LogsDailyTest(unittest.TestCase):
    def test_no_errors_no_card(self):
        with mock.patch.object(valoris_logs_daily, "job_failure_groups", return_value=[]), \
                mock.patch.object(valoris_logs_daily, "message_groups", return_value=[]), \
                mock.patch.object(valoris_logs_daily, "create_card") as create:
            valoris_logs_daily.main()
        create.assert_not_called()

    def test_render_job_failure_group(self):
        group = {"kind": "job_failure", "count": 3, "fingerprint": "abc123def456", "job_class": "DiscoveryJob",
                 "exception": "NoListingsFoundError", "queue": "default", "message": "Spider jansen found N",
                 "first_seen": "2026-11-01 00:00:00Z", "last_seen": "2026-11-01 01:00:00Z",
                 "backtrace": ["app/domains/scraping/jobs/discovery_job.rb:139"], "example_arguments": None}
        out = valoris_logs_daily.render([group], 0, 86400)
        self.assertIn("## 1. [job_failure] NoListingsFoundError in DiscoveryJob", out)
        self.assertIn("- fingerprint: `abc123def456`", out)
        self.assertIn("app/domains/scraping/jobs/discovery_job.rb:139", out)

    def test_card_key_is_per_day(self):
        group = {"kind": "worker_error", "count": 1, "fingerprint": "f", "message": "m", "first_seen": "a",
                 "last_seen": "b", "example": "e"}
        with mock.patch.object(valoris_logs_daily, "job_failure_groups", return_value=[group]), \
                mock.patch.object(valoris_logs_daily, "message_groups", return_value=[]), \
                mock.patch.object(valoris_logs_daily, "create_card") as create:
            valoris_logs_daily.main()
        stage, title, _body, key = create.call_args.args
        self.assertEqual(stage, "logs")
        self.assertTrue(key.startswith("valoris-flow:logs:"))


class IssuesDailyTest(unittest.TestCase):
    def test_creates_daily_card(self):
        with mock.patch.object(valoris_issues_daily, "create_card") as create:
            valoris_issues_daily.main()
        stage, title, body, key = create.call_args.args
        self.assertEqual(stage, "issues")
        self.assertIn("not labeled `triaged`", body)
        self.assertTrue(key.startswith("valoris-flow:issues:"))


if __name__ == "__main__":
    unittest.main()
