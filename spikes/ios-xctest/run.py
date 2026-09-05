"""Experimental pymobiledevice3 launch path; xcodebuild is the native baseline."""

import argparse
import asyncio
import json
import logging
import time
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path

from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
from pymobiledevice3.services.dvt.testmanaged.dtx_services import XCUITestListener
from pymobiledevice3.services.dvt.testmanaged.xcuitest import TestConfig, XCUITestService


class Listener(XCUITestListener):
    def __init__(self):
        self.cases = []
        self.failures = []
        self.plan_finished = False
        self.initialization_errors = []
        self.initialization_failed = asyncio.Event()

    async def test_case_did_start(self, test_class, method):
        print(f"START {test_class}.{method}", flush=True)

    async def test_case_did_finish(self, result):
        self.cases.append(asdict(result))
        print(f"{result.status.upper()} {result.method} {result.duration:.2f}s", flush=True)

    async def test_case_did_fail(self, test_class, method, message, file, line):
        self.failures.append({"test_class": test_class, "method": method, "message": message, "file": file, "line": line})
        print(f"FAILURE {method}: {message}", flush=True)

    async def did_finish_executing_test_plan(self):
        self.plan_finished = True

    async def log_message(self, message):
        logging.info("RUNNER %s", message)

    async def initialization_for_ui_testing_did_fail(self, error):
        details = {"domain": error.domain, "code": error.code, "user_info": error.user_info}
        self.initialization_errors.append(details)
        self.initialization_failed.set()
        print("INITIALIZATION_FAILED " + json.dumps(details, default=str), flush=True)

    async def did_fail_to_bootstrap(self, error):
        await self.initialization_for_ui_testing_did_fail(error)


def plan_passed(cases, plan_finished, failures, initialization_errors):
    # XCTest may report the explicitly skipped live-session case in its callbacks.
    executed = [case for case in cases if (
        case["test_class"], case["method"], case["status"]
    ) != ("LiveSessionTests", "testCommandSession", "skipped")]
    expected = {("AgentSomaTests", method, "passed") for method in (
        "test01ObservationAndTap", "test02Text", "test03Swipe", "test04Calculator"
    )}
    actual = {(case["test_class"], case["method"], case["status"]) for case in executed}
    return (plan_finished and not failures and not initialization_errors
            and len(executed) == len(expected) and actual == expected)


async def run(args):
    output = Path(__file__).parent / "evidence" / ("pmd-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    output.mkdir(parents=True)
    print(f"RESULT_DIRECTORY={output}", flush=True)
    logging.basicConfig(filename=output / "xctest.log", level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    listener = Listener()
    result = {"started_at": datetime.now(timezone.utc).isoformat(), "status": "running"}
    started = time.monotonic()
    try:
        async with asyncio.timeout(240):
            async with RemoteServiceDiscoveryService((args.host, args.port)) as rsd:
                lock_file = output / "lock-state.json"
                preflight = await asyncio.create_subprocess_exec(
                    "xcrun", "devicectl", "device", "info", "lockState", "--device", rsd.udid,
                    "--timeout", "10", "--quiet", "--json-output", str(lock_file),
                    stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE,
                )
                _, preflight_error = await preflight.communicate()
                if preflight.returncode:
                    raise RuntimeError("lock_state_unavailable: " + preflight_error.decode(errors="replace"))
                result["lock_state_provider"] = "devicectl"
                result["lock_state_before"] = json.loads(lock_file.read_text())["result"]
                required = result["lock_state_before"].get("passcodeRequired")
                if required is True:
                    raise RuntimeError("device_locked: unlock the iPhone before starting XCTest")
                if required is not False:
                    raise RuntimeError("lock_state_unconfirmed: XCTest was not started")
                cfg = await TestConfig.create_for(
                    rsd, "com.somnus.agentsoma.spike.tests.xctrunner", "com.somnus.agentsoma.spike.fixture"
                )
                cfg.tests_to_skip = ["LiveSessionTests/testCommandSession"]
                execution = asyncio.create_task(XCUITestService(rsd).run(cfg, timeout=180, listener=listener))
                failed = asyncio.create_task(listener.initialization_failed.wait())
                try:
                    await asyncio.wait({execution, failed}, return_when=asyncio.FIRST_COMPLETED)
                    if listener.initialization_failed.is_set():
                        raise RuntimeError("UI testing initialization failed; see initialization_errors")
                    await execution
                finally:
                    execution.cancel()
                    failed.cancel()
                    await asyncio.gather(execution, failed, return_exceptions=True)
        result["status"] = "passed" if plan_passed(
            listener.cases, listener.plan_finished, listener.failures, listener.initialization_errors
        ) else "not_passed"
    except Exception as error:
        result["status"] = "error"
        result["error"] = {"type": type(error).__name__, "message": str(error)}
    result.update({"cases": listener.cases, "failures": listener.failures, "initialization_errors": listener.initialization_errors,
                   "plan_finished": listener.plan_finished,
                   "total_ms": round((time.monotonic() - started) * 1000)})
    (output / "result.json").write_text(json.dumps(result, indent=2, default=str))
    print(json.dumps(result, indent=2, default=str))
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, required=True)
    raise SystemExit(asyncio.run(run(parser.parse_args())))
