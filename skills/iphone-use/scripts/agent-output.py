#!/usr/bin/env python3
"""Present/archive one CLI stdout stream. Never invokes the CLI or retries input."""
import argparse
import copy
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile


def compact(reply):
    result = copy.deepcopy(reply)
    action = result.get("action", {})
    observation = result.get("observation", {})
    # Preserve unsuccessful/uncertain replies verbatim, including every guard fact.
    if (action.get("ok") is True and action.get("outcome") == "completed"
            and observation.get("ok") is True
            and observation.get("result", {}).get("screenshot")):
        details = action.get("result", {})
        # The fresh observation is displayed; the earlier sampled action frame and
        # comparison internals remain in the raw stdout and full CLI receipt.
        details.pop("frame", None)
        stability = details.get("stability")
        if isinstance(stability, dict):
            for key in ("hash", "referenceHash", "comparison"):
                stability.pop(key, None)
    return result


def archive(reply, folder):
    artifacts = {"stdout": str(folder / "stdout.jsonl")}
    observation = reply.get("observation", {})
    if observation.get("ok") is True:
        observed = observation.get("result", {})
    elif reply.get("ok") is True and reply.get("result", {}).get("screenshot"):
        observed = reply["result"]
    else:
        observed = {}
    sources = [(observed.get("screenshot"), "screenshot.png", "screenshot"),
               (observed.get("snapshot"), "snapshot.json", "snapshot"),
               (reply.get("receipt"), "receipt.json", "receipt")]
    errors = []
    for source, name, key in sources:
        if not source:
            continue
        try:
            target = folder / name
            shutil.copyfile(source, target)
            target.chmod(0o600)
            artifacts[key] = str(target)
        except (OSError, TypeError) as error:
            errors.append(f"{key}: {error}")
    return artifacts, errors


def present(stream, output, evidence=None):
    folder = None
    archive_errors = []
    try:
        if evidence is not None:
            Path(evidence).mkdir(parents=True, exist_ok=True, mode=0o700)
        folder = Path(tempfile.mkdtemp(prefix="iphone-use-", dir=evidence)).resolve()
        raw_file = (folder / "stdout.jsonl").open("x", encoding="utf-8")
        (folder / "stdout.jsonl").chmod(0o600)
    except OSError as error:
        archive_errors.append(str(error))
        raw_file = None

    lines = []
    reply = None
    malformed = False
    try:
        for line in stream:
            lines.append(line)
            if raw_file is not None:
                try:
                    raw_file.write(line)
                except OSError as error:
                    archive_errors.append(str(error))
                    try:
                        raw_file.close()
                    except OSError:
                        pass
                    raw_file = None
            try:
                value = json.loads(line)
                if not isinstance(value, dict):
                    malformed = True
                elif value.get("event") in ("connection_progress", "setup_progress"):
                    print(json.dumps(value, ensure_ascii=False), file=output, flush=True)
                elif reply is None:
                    reply = value
                else:
                    malformed = True
            except json.JSONDecodeError:
                if line.strip():
                    malformed = True
    finally:
        if raw_file is not None:
            try:
                raw_file.close()
            except OSError as error:
                archive_errors.append(str(error))

    if reply is None or malformed:
        # No guessed action outcome. Retain incomplete/mixed output and let the
        # caller diagnose it without rerunning the command.
        print(json.dumps({"outputError": "CLI stdout has no single complete final JSON reply",
                          "rawOutput": str(folder / "stdout.jsonl") if folder else None,
                          "unparsedOutput": "".join(lines),
                          "archiveErrors": archive_errors}, ensure_ascii=False), file=output, flush=True)
        return 1
    artifacts = {}
    if folder is not None and not archive_errors:
        try:
            artifacts, errors = archive(reply, folder)
            archive_errors.extend(errors)
        except (OSError, TypeError, AttributeError) as error:
            archive_errors.append(str(error))
    # Compact only when the complete original output was safely persisted.
    shown = compact(reply) if artifacts and not archive_errors else reply
    shown["artifacts"] = artifacts
    if archive_errors:
        shown["archiveErrors"] = archive_errors
    print(json.dumps(shown, ensure_ascii=False), file=output, flush=True)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", help="Requested evidence directory; otherwise use private temporary storage")
    args = parser.parse_args()
    os.umask(0o077)
    return present(sys.stdin, sys.stdout, args.evidence)


if __name__ == "__main__":
    sys.exit(main())
