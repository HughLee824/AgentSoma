#!/usr/bin/env python3
"""Observe an existing GitHub AI reviewer. GET-only; never request or approve a review."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SHA = re.compile(r"[0-9a-f]{40}\Z")
ADAPTERS = ("codex-summary-v1", "github-reviews")
MAX_PAGES = 20
MAX_RESPONSE = 10 * 1024 * 1024


def positive_integer(value):
    if isinstance(value, bool) or not re.fullmatch(r"[1-9][0-9]*", str(value)):
        raise ValueError("Expected a positive integer")
    return int(value)


def repository_name(value):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise ValueError("Expected owner/repository")
    return value


def load_config(path):
    config = json.loads(path.read_text())
    if type(config.get("schema_version")) is not int or config["schema_version"] != 1 or config.get("mode") != "advisory":
        raise ValueError("Only schema version 1 and advisory mode are supported")
    provider = config["provider"]
    if provider["adapter"] not in ADAPTERS:
        raise ValueError("Unsupported provider adapter")
    for key in ("id", "login"):
        if not isinstance(provider[key], str) or not re.fullmatch(r"[A-Za-z0-9_\[\]-]+", provider[key]):
            raise ValueError("Invalid provider identity")
    if type(provider["user_id"]) is not int:
        raise ValueError("Provider user_id must be a numeric GitHub account ID")
    positive_integer(provider["user_id"])
    if not isinstance(config["policy_files"], list) or not config["policy_files"]:
        raise ValueError("Policy files are required")
    return config


def policy_digest(config, root):
    digest = hashlib.sha256(json.dumps(config, sort_keys=True).encode())
    for name in config["policy_files"]:
        if not isinstance(name, str):
            raise ValueError("Invalid policy path")
        path = (root / name).resolve()
        if root.resolve() not in path.parents or path.stat().st_size > 1024 * 1024:
            raise ValueError("Policy must be a bounded file inside the trusted checkout")
        digest.update(name.encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Do not forward credentials to a destination supplied by a response.
        return None


class GitHub:
    def __init__(self, repository, token=None):
        self.repository = repository_name(repository)
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect)

    def get(self, endpoint):
        headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
                   "User-Agent": "advisory-review-pilot"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        url = f"https://api.github.com/repos/{self.repository}/{endpoint}"
        with self.opener.open(urllib.request.Request(url, headers=headers), timeout=20) as response:
            payload = response.read(MAX_RESPONSE + 1)
        if len(payload) > MAX_RESPONSE:
            raise ValueError("GitHub response exceeded size limit")
        return json.loads(payload)

    def pages(self, endpoint):
        items = []
        for page in range(1, MAX_PAGES + 1):
            batch = self.get(f"{endpoint}?per_page=100&page={page}")
            if not isinstance(batch, list):
                raise ValueError("Expected a GitHub list response")
            items.extend(batch)
            if len(batch) < 100:
                return items
        raise ValueError("Pagination limit reached; results may be incomplete")


def trusted(item, provider):
    user = item.get("user") or {}
    return (user.get("type") == "Bot" and user.get("login") == provider["login"]
            and user.get("id") == provider["user_id"])


def result(status, reason, **fields):
    return {"status": status, "reason": reason, "reviewed_head_sha": None,
            "reviewed_base_sha": None, "has_findings": None, "has_unresolved_findings": None,
            "source_id": None, "source_kind": None, **fields}


def codex_summary(comments, provider):
    candidates = [item for item in comments if trusted(item, provider)
                  and "<!-- codex-pull-request-review-summary -->" in (item.get("body") or "")]
    if not candidates:
        return result("missing", "No recognized provider summary; this is not a clean review")
    item = max(candidates, key=lambda entry: (entry["updated_at"], entry["id"]))
    source = {"source_id": positive_integer(item["id"]), "source_kind": "issuecomment"}
    matches = re.findall(r"<!-- codex-review-state:v1 (.*?) -->", item["body"], re.DOTALL)
    try:
        if len(matches) != 1:
            raise ValueError("Unknown summary format")
        state = json.loads(matches[0])["code_review"]
        status, sha = state["status"], state["commit_sha"]
        if sha is not None and (not isinstance(sha, str) or not SHA.fullmatch(sha)):
            raise ValueError("Invalid commit identity")
        if status in ("queued", "pending", "in_progress", "running"):
            return result("pending", "Provider reports review in progress", reviewed_head_sha=sha, **source)
        if status != "completed":
            return result("unavailable", "Provider has not reported a supported completed state", **source)
        if not sha or any(type(state[key]) is not bool for key in ("has_any_findings", "has_unresolved_findings")):
            raise ValueError("Incomplete completed result")
        if state["has_unresolved_findings"] and not state["has_any_findings"]:
            raise ValueError("Contradictory finding state")
        return result("completed", "Provider reports completion; base revision and review coverage are unreported",
                      reviewed_head_sha=sha, has_findings=state["has_any_findings"],
                      has_unresolved_findings=state["has_unresolved_findings"], **source)
    except (KeyError, TypeError, ValueError):
        return result("unavailable", "Unrecognized or malformed provider summary; inspect the provider directly", **source)


def github_reviews(reviews, provider):
    candidates = [item for item in reviews if trusted(item, provider) and item.get("submitted_at")]
    if not candidates:
        return result("missing", "No submitted review from the configured bot")
    item = max(candidates, key=lambda entry: (entry["submitted_at"], entry["id"]))
    sha = item.get("commit_id")
    source = {"source_id": positive_integer(item["id"]), "source_kind": "pullrequestreview"}
    if not isinstance(sha, str) or not SHA.fullmatch(sha) or item.get("state") not in (
            "COMMENTED", "APPROVED", "CHANGES_REQUESTED"):
        return result("unavailable", "Review dismissed, unsupported or missing its commit identity", **source)
    # COMMENTED and APPROVED cannot establish absence of findings or resolved threads.
    return result("completed", "Bot submitted a review; findings, resolution and base coverage remain unknown",
                  reviewed_head_sha=sha, **source)


def pr_identity(pr):
    head, base = pr["head"]["sha"], pr["base"]["sha"]
    if not all(isinstance(sha, str) and SHA.fullmatch(sha) for sha in (head, base)):
        raise ValueError("Invalid PR commit identity")
    return {"head_sha": head, "base_sha": base}


def collect(api, number, config, digest):
    number = positive_integer(number)
    provider = config["provider"]
    receipt = {"schema_version": 1, "mode": "advisory", "repository": api.repository,
               "pr_number": number, "provider": provider["id"], "adapter": provider["adapter"],
               "observer_policy_sha256": digest, "reviewer_policy_sha256": None,
               "collector_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               "head_sha": None, "base_sha": None,
               "observed_at": datetime.now(timezone.utc).isoformat(),
               "model": None, "prompt_version": None, "cost": None}
    try:
        before = pr_identity(api.get(f"pulls/{number}"))
        receipt.update(before)
        if provider["adapter"] == "codex-summary-v1":
            observation = codex_summary(api.pages(f"issues/{number}/comments"), provider)
        else:
            observation = github_reviews(api.pages(f"pulls/{number}/reviews"), provider)
        after = pr_identity(api.get(f"pulls/{number}"))
        if before != after:
            observation.update(status="stale", reason="PR head or base changed while collecting; run again")
        elif observation["reviewed_head_sha"] and observation["reviewed_head_sha"] != before["head_sha"]:
            observation.update(status="stale", reason="Provider result belongs to an older or different head")
        receipt.update(observation)
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        # Error messages can contain response bodies, URLs or credentials. Do not publish them.
        receipt.update(result("unavailable", "Collection failed (" + type(error).__name__ + "); inspect configuration and provider availability"))
    return receipt


def render(receipt):
    rows = [("Provider / adapter", receipt["provider"] + " / " + receipt["adapter"]),
            ("Observation", receipt["status"]), ("PR head", receipt["head_sha"]),
            ("Observed base", receipt["base_sha"]), ("Reviewed head", receipt["reviewed_head_sha"]),
            ("Reviewed base", receipt["reviewed_base_sha"]), ("Has findings", receipt["has_findings"]),
            ("Has unresolved findings", receipt["has_unresolved_findings"])]
    lines = ["## Advisory review observation", "", "This is a collector result, not an AI approval or a merge gate.", "",
             "| Field | Value |", "| --- | --- |"]
    lines.extend(f"| {key} | `{value if value is not None else 'unknown'}` |" for key, value in rows)
    lines.extend(["", receipt["reason"], "", "Base coverage, model, prompt, cost and finding dispositions are not inferred."])
    if receipt["source_id"]:
        url = (f"https://github.com/{receipt['repository']}/pull/{receipt['pr_number']}"
               f"#{receipt['source_kind']}-{receipt['source_id']}")
        lines.extend(["", f"[Provider evidence]({url})"])
    return "\n".join(lines) + "\n"


def event_number(event):
    if "pull_request" in event:
        return positive_integer(event["pull_request"]["number"])
    if "issue" in event and "pull_request" in event["issue"]:
        return positive_integer(event["issue"]["number"])
    if "inputs" in event:
        return positive_integer(event["inputs"]["pr_number"])
    raise ValueError("Expected a pull request event or workflow dispatch PR number")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / ".github/review-pilot.json")
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--pr", type=positive_integer)
    source.add_argument("--event", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--summary", type=Path)
    args = parser.parse_args()
    config = load_config(args.config)
    number = args.pr if args.pr else event_number(json.loads(args.event.read_text()))
    api = GitHub(args.repository or "", os.environ.get("GITHUB_TOKEN"))
    receipt = collect(api, number, config, policy_digest(config, ROOT))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, indent=2) + "\n")
    if args.summary:
        args.summary.parent.mkdir(parents=True, exist_ok=True)
        args.summary.write_text(render(receipt))
    print(f"Advisory observation: {receipt['status']}; this is not an AI approval.")
    # Findings do not fail this job. Inability to collect remains visible as a job failure.
    return 1 if receipt["status"] == "unavailable" else 0


if __name__ == "__main__":
    sys.exit(main())
