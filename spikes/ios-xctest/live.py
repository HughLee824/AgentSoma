"""Bounded USB command-session spike. Run start, then send JSON on call's stdin."""

import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from uuid import uuid4

ROOT = Path(__file__).resolve().parent


def start(udid):
    directory = ROOT / "evidence" / ("live-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    directory.mkdir(parents=True)
    config = {"host": "127.0.0.1", "port": 47821, "token": secrets.token_hex(32)}
    with open(directory / "session.json", "x", opener=lambda path, flags: os.open(path, flags, 0o600)) as file:
        json.dump(config, file)
    environment = dict(os.environ, TEST_RUNNER_AGENTSOMA_SESSION_TOKEN=config["token"])
    print(f"SESSION_DIRECTORY={directory}", flush=True)
    processes = []
    try:
        with (directory / "forward.log").open("w") as forward_log, (directory / "xcode.log").open("w") as xcode_log:
            processes.append(subprocess.Popen(
                ["/opt/homebrew/bin/iproxy", "--udid", udid, "--source", "127.0.0.1", "47821:47821"],
                stdout=forward_log, stderr=subprocess.STDOUT,
            ))
            time.sleep(0.2)
            if processes[0].poll() is not None:
                raise RuntimeError("USB forwarder exited; inspect forward.log")
            began = time.monotonic()
            processes.append(subprocess.Popen([
                "xcodebuild", "test-without-building",
                "-xctestrun", "build/Build/Products/AgentSomaSpike_iphoneos18.0-arm64.xctestrun",
                "-destination", f"platform=iOS,id={udid}", "-destination-timeout", "15",
                "-parallel-testing-enabled", "NO",
                "-only-testing:AgentSomaTests/LiveSessionTests/testCommandSession",
                "-resultBundlePath", str(directory / "test.xcresult"),
            ], cwd=ROOT, env=environment, stdout=xcode_log, stderr=subprocess.STDOUT))
            (directory / "processes.json").write_text(json.dumps({
                "forwarderPid": processes[0].pid, "xcodebuildPid": processes[1].pid,
            }, indent=2))
            code = processes[-1].wait()
            (directory / "launcher.json").write_text(json.dumps({
                "exitCode": code, "wallMs": (time.monotonic() - began) * 1000,
            }, indent=2))
            return code
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def call(directory, command):
    directory = Path(directory)
    config = json.loads((directory / "session.json").read_text())
    request = dict(command, id=uuid4().hex)
    payload = dict(request, token=config["token"])
    began = time.monotonic()
    # Never automatically replay a command: a timeout can have an unknown device outcome.
    with socket.create_connection((config["host"], config["port"]), timeout=90) as connection:
        connection.sendall(json.dumps(payload, ensure_ascii=False).encode() + b"\n")
        with connection.makefile("rb") as stream:
            line = stream.readline(16 * 1024 * 1024)
        if not line.endswith(b"\n"):
            raise RuntimeError("Incomplete response; command outcome unknown. Do not blindly retry.")
    response = json.loads(line)
    if response.get("id") != request["id"]:
        raise RuntimeError("Response ID mismatch")
    response["hostMs"] = (time.monotonic() - began) * 1000
    prefix = directory / (f"{response['sequence']:03d}-" + request["op"])
    result = response.get("result", {})
    screenshot = result.pop("screenshotBase64", None)
    if screenshot:
        prefix.with_suffix(".png").write_bytes(base64.b64decode(screenshot, validate=True))
        result["screenshotPath"] = str(prefix.with_suffix(".png"))
    response["request"] = request
    response["evidencePath"] = str(prefix.with_suffix(".json"))
    prefix.with_suffix(".json").write_text(json.dumps(response, indent=2, ensure_ascii=False))
    return response


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="operation", required=True)
    launching = subcommands.add_parser("start")
    launching.add_argument("--udid", required=True)
    sending = subcommands.add_parser("call")
    sending.add_argument("--session", required=True, type=Path)
    args = parser.parse_args()
    if args.operation == "start":
        return start(args.udid)
    response = call(args.session, json.load(sys.stdin))
    summary = dict(response)
    summary["result"] = dict(response.get("result", {}))
    nodes = summary["result"].pop("nodes", None)
    if nodes is not None:
        summary["result"]["nodeCount"] = len(nodes)
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0 if response["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
