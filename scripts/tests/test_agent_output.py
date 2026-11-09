import io
import json
import os
from pathlib import Path
import select
import shlex
import subprocess
import sys
import tempfile
import types
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "skills/iphone-use/scripts/agent-output.py"
MODULE = types.ModuleType("skill_output")
exec(compile(SCRIPT.read_text(), str(SCRIPT), "exec"), MODULE.__dict__)


class AgentOutputHelperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.evidence = self.root / "evidence"
        self.image = self.root / "source.png"
        self.image.write_bytes(b"image evidence")
        self.snapshot = self.root / "snapshot.json"
        self.snapshot.write_text('{"nodes":[]}')
        self.receipt = self.root / "receipt.json"
        self.receipt.write_text('{"full":"diagnostics"}')

    def reply(self, outcome="completed"):
        return {"ok": outcome == "completed", "session": "s-test", "receipt": str(self.receipt),
                "action": {"ok": outcome == "completed", "outcome": outcome,
                           "result": {"execution": {"started": True}, "inputAction": {"automaticReplayAllowed": False},
                                      "frame": {"hash": "original"},
                                      "stability": {"stable": False, "reason": "dynamic_or_transitioning",
                                                    "hash": "hash", "comparison": {"changed": True}}}},
                "observation": {"ok": True, "result": {"screenshot": str(self.image),
                                                       "snapshot": str(self.snapshot), "text": "o2 current"}}}

    def present(self, reply, evidence=None):
        stream = json.dumps(reply) + "\n"
        output = io.StringIO()
        status = MODULE.present(io.StringIO(stream), output, self.evidence if evidence is None else evidence)
        return status, json.loads(output.getvalue()), stream

    def test_archives_before_source_removal_and_only_compacts_completed_diagnostics(self):
        source = self.reply()
        status, shown, stream = self.present(source)
        self.assertEqual(status, 0)
        self.image.unlink()
        artifacts = shown["artifacts"]
        self.assertEqual(Path(artifacts["stdout"]).read_text(), stream)
        self.assertEqual(Path(artifacts["screenshot"]).read_bytes(), b"image evidence")
        self.assertEqual(Path(artifacts["snapshot"]).read_text(), self.snapshot.read_text())
        self.assertEqual(Path(artifacts["receipt"]).read_text(), self.receipt.read_text())
        self.assertEqual(Path(artifacts["stdout"]).stat().st_mode & 0o777, 0o600)
        self.assertEqual(Path(artifacts["stdout"]).parent.stat().st_mode & 0o777, 0o700)
        self.assertNotIn("frame", shown["action"]["result"])
        self.assertEqual(shown["action"]["result"]["stability"],
                         {"stable": False, "reason": "dynamic_or_transitioning"})
        self.assertEqual(shown["observation"], source["observation"])
        self.assertIn("frame", source["action"]["result"])

    def test_unknown_and_rejection_keep_all_execution_and_guard_facts(self):
        for outcome in ("unknown", "not_dispatched", "prepared"):
            source = self.reply(outcome)
            status, shown, _ = self.present(source)
            self.assertEqual(status, 0)
            self.assertEqual(shown["action"], source["action"])
            self.assertEqual(shown["observation"], source["observation"])

    def test_archive_error_does_not_compact_or_erase_action(self):
        blocker = self.root / "not-a-directory"
        blocker.write_text("existing")
        source = self.reply()
        status, shown, _ = self.present(source, blocker)
        self.assertEqual(status, 0)
        self.assertTrue(shown["archiveErrors"])
        self.assertEqual(shown["action"], source["action"])
        self.assertEqual(blocker.read_text(), "existing")

    def test_partial_output_is_preserved_without_guessing_an_outcome(self):
        output = io.StringIO()
        status = MODULE.present(io.StringIO('{"action":'), output, self.evidence)
        shown = json.loads(output.getvalue())
        self.assertEqual(status, 1)
        self.assertNotIn("action", shown)
        self.assertEqual(Path(shown["rawOutput"]).read_text(), '{"action":')

    def test_progress_is_forwarded_before_eof(self):
        process = subprocess.Popen([sys.executable, str(SCRIPT), "--evidence", str(self.evidence)],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True)
        try:
            progress = {"event": "connection_progress", "requiresUserAction": True}
            process.stdin.write(json.dumps(progress) + "\n")
            process.stdin.flush()
            ready, _, _ = select.select([process.stdout], [], [], 3)
            self.assertTrue(ready, "authorization progress must not wait for command completion")
            self.assertEqual(json.loads(process.stdout.readline()), progress)
            process.stdin.write(json.dumps({"ok": True, "mode": "runner"}) + "\n")
            process.stdin.close()
            process.wait(timeout=3)
            reply = json.loads(process.stdout.read())
            self.assertEqual(reply["mode"], "runner")
            self.assertEqual(len(Path(reply["artifacts"]["stdout"]).read_text().splitlines()), 2)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()

    def test_pipefail_preserves_cli_exit_when_helper_succeeds(self):
        source = json.dumps(self.reply("unknown"))
        command = ("set -o pipefail; (printf '%s\\n' " + shlex.quote(source) + "; exit 7) | "
                   + shlex.join([sys.executable, str(SCRIPT), "--evidence", str(self.evidence)]))
        result = subprocess.run(["/bin/bash", "-c", command], capture_output=True, text=True)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(json.loads(result.stdout)["action"]["outcome"], "unknown")


if __name__ == "__main__":
    unittest.main()
