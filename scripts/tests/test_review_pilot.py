"""Advisory observation must never turn absent, forged or stale evidence into a pass."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("review_pilot", ROOT / "scripts/review/pilot.py")
pilot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pilot)
CONFIG = {"schema_version": 1, "mode": "advisory", "policy_files": ["REVIEW.md"],
          "provider": {"id": "fixture", "adapter": "codex-summary-v1", "login": "fixture[bot]", "user_id": 42}}
HEAD, BASE, OLD = "a" * 40, "b" * 40, "c" * 40


def summary(sha=HEAD, status="completed", findings=False, unresolved=False):
    state = {"code_review": {"commit_sha": sha, "status": status,
                            "has_any_findings": findings, "has_unresolved_findings": unresolved}}
    return {"id": 123, "updated_at": "2026-01-01T00:00:00Z",
            "user": {"login": CONFIG["provider"]["login"], "id": CONFIG["provider"]["user_id"], "type": "Bot"},
            "body": "<!-- codex-pull-request-review-summary -->\n<!-- codex-review-state:v1 " + json.dumps(state) + " -->"}


def review(sha=HEAD, state="COMMENTED"):
    return {"id": 456, "submitted_at": "2026-01-01T00:00:00Z", "commit_id": sha,
            "state": state, "user": summary()["user"], "body": "Untrusted prose"}


class API:
    repository = "example/project"

    def __init__(self, items=None, after=None):
        self.items = items if items is not None else [summary()]
        self.before = {"head": {"sha": HEAD}, "base": {"sha": BASE}}
        self.after = after or self.before
        self.calls = 0

    def get(self, endpoint):
        self.calls += 1
        return self.before if self.calls == 1 else self.after

    def pages(self, endpoint):
        return self.items


class ReviewPilotTests(unittest.TestCase):
    def observe(self, items=None, after=None, config=None):
        return pilot.collect(API(items, after), 7, config or CONFIG, "d" * 64)

    def test_completed_head_match_preserves_unknown_base_and_model(self):
        receipt = self.observe()
        self.assertEqual(receipt["status"], "completed")
        self.assertEqual(receipt["head_sha"], HEAD)
        self.assertIs(receipt["has_findings"], False)
        for key in ("reviewed_base_sha", "reviewer_policy_sha256", "model", "prompt_version", "cost"):
            self.assertIsNone(receipt[key])
        self.assertIn("not an AI approval", pilot.render(receipt))

    def test_findings_and_resolution_are_separate(self):
        for unresolved in (True, False):
            receipt = self.observe([summary(findings=True, unresolved=unresolved)])
            self.assertEqual(receipt["status"], "completed")
            self.assertIs(receipt["has_findings"], True)
            self.assertIs(receipt["has_unresolved_findings"], unresolved)

    def test_spoofed_login_id_or_human_is_ignored(self):
        for key, value in (("login", "imposter[bot]"), ("id", 999), ("type", "User")):
            item = summary()
            item["user"][key] = value
            self.assertEqual(self.observe([item])["status"], "missing")

    def test_no_comment_is_not_zero_findings(self):
        receipt = self.observe([])
        self.assertEqual(receipt["status"], "missing")
        self.assertIsNone(receipt["has_findings"])

    def test_pending_and_failed_are_not_completed(self):
        for status, expected in (("in_progress", "pending"), ("queued", "pending"),
                                 ("failed", "unavailable"), (None, "unavailable")):
            with self.subTest(status=status):
                receipt = self.observe([summary(status=status)])
                self.assertEqual(receipt["status"], expected)
                self.assertIsNone(receipt["has_findings"])

    def test_completed_requires_full_sha_boolean_flags_and_consistency(self):
        for item in (summary(sha=HEAD[:7]), summary(sha=None), summary(findings="false"),
                     summary(findings=None), summary(findings=False, unresolved=True)):
            self.assertEqual(self.observe([item])["status"], "unavailable")

    def test_malformed_or_changed_format_does_not_fall_back_to_old_success(self):
        for body in ("<!-- codex-review-state:v2 {} -->", "<!-- codex-review-state:v1 {oops} -->",
                     "<!-- codex-review-state:v1 {} -->", "<!-- codex-review-state:v1 null -->"):
            item = summary()
            item.update(id=999, updated_at="2026-01-02T00:00:00Z",
                        body="<!-- codex-pull-request-review-summary -->\n" + body)
            self.assertEqual(self.observe([summary(), item])["status"], "unavailable")

    def test_older_head_is_stale_even_when_provider_reports_completed(self):
        receipt = self.observe([summary(sha=OLD)])
        self.assertEqual(receipt["status"], "stale")
        self.assertEqual(receipt["reviewed_head_sha"], OLD)

    def test_head_or_base_change_during_fetch_is_stale(self):
        for key in ("head", "base"):
            after = {"head": {"sha": HEAD}, "base": {"sha": BASE}}
            after[key]["sha"] = OLD
            self.assertEqual(self.observe(after=after)["status"], "stale")

    def test_untrusted_prose_is_never_copied_to_receipt_or_summary(self):
        item = summary()
        item["body"] += "\nSECRET <script>bad()</script> @everyone $(touch OWNED)"
        receipt = self.observe([item])
        self.assertNotIn("SECRET", json.dumps(receipt) + pilot.render(receipt))
        self.assertNotIn("<script>", pilot.render(receipt))

    def test_network_errors_are_unavailable_and_do_not_leak_message(self):
        api = API()
        with patch.object(api, "pages", side_effect=OSError("SECRET response body")):
            receipt = pilot.collect(api, 7, CONFIG, "d" * 64)
        self.assertEqual(receipt["status"], "unavailable")
        self.assertNotIn("SECRET", json.dumps(receipt))

    def test_malformed_api_items_are_unavailable(self):
        self.assertEqual(self.observe(["unexpected"])["status"], "unavailable")

    def test_cli_findings_do_not_fail_but_collection_failures_do(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "receipt.json"
            rendered = Path(directory) / "summary.md"
            for status, expected in (("completed", 0), ("missing", 0), ("pending", 0),
                                     ("stale", 0), ("unavailable", 1)):
                receipt = self.observe([summary(findings=True, unresolved=True)])
                receipt["status"] = status
                argv = ["pilot.py", "--repository", "example/project", "--pr", "7",
                        "--output", str(output), "--summary", str(rendered)]
                with patch("sys.argv", argv), patch.object(pilot, "collect", return_value=receipt):
                    self.assertEqual(pilot.main(), expected)
                self.assertEqual(json.loads(output.read_text())["status"], status)
                self.assertIn("not an AI approval", rendered.read_text())

    def test_generic_provider_does_not_infer_clean_from_approval(self):
        config = copy.deepcopy(CONFIG)
        config["provider"].update(id="another-provider", adapter="github-reviews")
        for state in ("COMMENTED", "APPROVED", "CHANGES_REQUESTED"):
            receipt = self.observe([review(state=state)], config=config)
            self.assertEqual(receipt["status"], "completed")
            self.assertIsNone(receipt["has_findings"])
            self.assertIsNone(receipt["has_unresolved_findings"])
            self.assertEqual(receipt["source_kind"], "pullrequestreview")

    def test_generic_adapter_excludes_pending_and_rejects_dismissed(self):
        provider = CONFIG["provider"]
        self.assertEqual(pilot.github_reviews([review(state="DISMISSED")], provider)["status"], "unavailable")
        pending = review()
        pending["submitted_at"] = None
        self.assertEqual(pilot.github_reviews([pending], provider)["status"], "missing")

    def test_pagination_reads_beyond_first_page_and_rejects_truncation(self):
        api = pilot.GitHub("example/project")
        with patch.object(api, "get", side_effect=[[{}] * 100, [summary()]]) as get:
            self.assertEqual(len(api.pages("issues/7/comments")), 101)
            self.assertEqual(get.call_count, 2)
        with patch.object(api, "get", return_value=[{}] * 100), patch.object(pilot, "MAX_PAGES", 2):
            with self.assertRaisesRegex(ValueError, "Pagination"):
                api.pages("issues/7/comments")

    def test_event_inputs_are_data_and_regular_issues_are_rejected(self):
        for event in ({"pull_request": {"number": 7}},
                      {"issue": {"number": 7, "pull_request": {}}}, {"inputs": {"pr_number": "7"}}):
            self.assertEqual(pilot.event_number(event), 7)
        for event in ({"issue": {"number": 7}}, {"inputs": {"pr_number": "$(touch OWNED)"}},
                      {"pull_request": {"number": True}}, {"inputs": {"pr_number": "-1"}}):
            with self.assertRaises(ValueError):
                pilot.event_number(event)

    def test_credentials_never_follow_redirects(self):
        self.assertIsNone(pilot.NoRedirect().redirect_request(None, None, 302, "", {}, "https://example.com"))

    def test_policy_hash_changes_and_cannot_escape_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "REVIEW.md"
            path.write_text("one")
            config = {**CONFIG, "policy_files": ["REVIEW.md"]}
            first = pilot.policy_digest(config, root)
            path.write_text("two")
            self.assertNotEqual(first, pilot.policy_digest(config, root))
            config["policy_files"] = [str(ROOT / "AGENTS.md")]
            with self.assertRaises(ValueError):
                pilot.policy_digest(config, root)

    def test_unknown_adapter_or_blocking_mode_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            for update in ({"mode": "required"}, {"schema_version": 2},
                           {"provider": {**CONFIG["provider"], "adapter": "shell-command"}}):
                path.write_text(json.dumps({**CONFIG, **update}))
                with self.assertRaises(ValueError):
                    pilot.load_config(path)

    def test_repository_config_and_policy_are_supported(self):
        config = pilot.load_config(ROOT / ".github/review-pilot.json")
        self.assertEqual(len(pilot.policy_digest(config, ROOT)), 64)

    def test_workflow_is_isolated_read_only_and_uses_default_branch(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/review-pilot.yml").read_text())
        self.assertEqual(workflow["permissions"], {"contents": "read", "issues": "read", "pull-requests": "read"})
        job = workflow["jobs"]["observe"]
        checkout = job["steps"][0]
        self.assertEqual(checkout["with"]["ref"], "${{ github.event.repository.default_branch }}")
        self.assertIs(checkout["with"]["persist-credentials"], False)
        for step in job["steps"]:
            if "run" in step:
                self.assertNotIn("${{", step["run"])
            if "uses" in step:
                self.assertRegex(step["uses"], r"@[0-9a-f]{40}$")
        self.assertNotIn("continue-on-error", job)


if __name__ == "__main__":
    unittest.main()
