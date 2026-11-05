# Advisory AI review pilot

Use the existing Codex GitHub integration as the first reviewer. [AGENTS.md](../../AGENTS.md) supplies concise custom rules; [REVIEW.md](../../REVIEW.md) owns project invariants. The [review procedure](../../docs/code-review.md) defines evidence, disposition and evaluation. The observer in this directory does not run a model, request a review, fix code, approve, merge or publish.

## Components and activation

| Component | Responsibility |
| --- | --- |
| Native reviewer integration | Performs the review and posts its findings. Configure it in the provider's own settings. |
| [Configuration](../../.github/review-pilot.json) | Selects a result adapter, expected bot login and numeric account ID, and local policy files. No model keys or repository-specific URLs. |
| [Collector](pilot.py) | Reads GitHub metadata, normalizes provider evidence and detects obsolete head results. Python 3.9+ standard library only. |
| [Workflow](../../.github/workflows/review-pilot.yml) | Runs the collector using the trusted default branch, with read-only permissions and a five-minute job limit. Stores a summary and a sanitized observation artifact for 30 days. |

The workflow must land on the default branch before its default-branch events and manual dispatch are available. A review event on the initial installation PR can start the new workflow before that happens; it reports that the pilot is not installed and makes no observation. Once installed, it observes PR creation, updates, ready-for-review, review submissions and issue-comment creation/edit/deletion. Ordinary issue comments are excluded. Every event fetches current PR metadata rather than trusting the event's old SHA. Concurrency cancels superseded jobs; a second metadata read detects head/base changes during collection. Results are snapshots, never durable approvals.

The observer does not change native reviewer triggers. In [Codex code review settings](https://chatgpt.com/codex/cloud/settings/general), verify repository access, Automatic review and Review trigger, including personal preferences when applicable. Select the intended author coverage and decide whether every push should be reviewed. Review after opening a PR does not prove subsequent pushes are covered. The [official integration guide](https://learn.chatgpt.com/docs/third-party/github) describes these settings and custom AGENTS.md rules. Check the provider's visible result for the latest head after a push; do not automatically post another trigger alongside an enabled native trigger.

Do not add this workflow to required checks or the CI `test` job. Collection failure is a visible failed advisory job; finding-bearing, missing, pending and stale observations are reported in the summary rather than failing CI. Existing branch protections, including resolved conversations, remain in force. No `continue-on-error` hides collector failures. Review submission events use GitHub's normal PR-event permission restrictions; the configured workflow checks out only the default branch and receives no model, signing or publication secrets. Protect workflow changes as high risk.

## Observe locally

For public repositories, no token is necessary; unauthenticated GitHub rate limits apply. For private repositories, supply a scoped `GITHUB_TOKEN` through the environment, with metadata, issues and pull-request read access. Never place the token in a command argument or config file.

```sh
python3 scripts/review/pilot.py --repository OWNER/REPO --pr 123 \
  --output .local/review-pilot/123.json --summary .local/review-pilot/123.md
```

In Actions, run **Review pilot (advisory) → Run workflow**, enter a PR number and inspect the job summary. This refreshes the observation; it does not trigger a new AI review. A missing result needs provider diagnosis, not a success claim. A pending result is refreshed on subsequent supported events or manual dispatch; this pilot has no polling timer and cannot detect a silent provider timeout without a later observation. GitHub may suppress events from some integrations, so verify event delivery during onboarding.

## Version-1 observation contract

Receipts identify the repository/PR, observed head/base SHAs, provider, adapter, observation time, collector code hash and observer policy/config hash. `reviewer_policy_sha256`, model, prompt version and cost remain `null`: the observer cannot prove what the remote reviewer loaded. The collector's policy hash describes only its own checkout, not reviewer policy compliance.

| Status | Meaning |
| --- | --- |
| `missing` | No recognized evidence from the configured bot; not zero findings. |
| `pending` | The provider reports a supported in-progress state. |
| `completed` | The provider reports completion/submission for the observed head. Coverage may still be unknown. |
| `stale` | A reviewed head differs from the PR head, or the PR head/base changed during collection. |
| `unavailable` | API failure, malformed evidence, dismissed review or unsupported provider state. |

`has_findings` and `has_unresolved_findings` are separate booleans or `null`. Unknown is never coerced to false. `source_kind` and `source_id` identify the original GitHub evidence; the observer generates the source link instead of trusting URLs in comment text. Raw comment/review bodies and error responses are never written to receipts or job summaries. Published artifacts contain only normalized metadata, not private captures or process logs.

Both current adapters lack a reviewed base SHA. They cannot prove coverage after a base change that occurred before collection, enforce prompt compliance, or prove zero defects. A future blocking adapter must provide stronger revision-bound evidence; these observations must not be promoted to a required pass check.

## Replace the reviewer

Two built-in result adapters are available:

- `codex-summary-v1`: reads the native Codex summary's observed `codex-review-state:v1` marker, verifying the bot login, numeric ID and `Bot` account type. It accepts a full head SHA and explicit finding flags. This marker is an observed implementation detail, not a documented stable API. Unsupported/malformed summaries become `unavailable`; do not infer success from prose or emoji.
- `github-reviews`: reads standard submitted GitHub reviews from the configured bot. It reports submission and head identity, but leaves finding and resolution flags unknown even for `APPROVED` or `COMMENTED`. `DISMISSED` is unavailable. Use this for a replacement service that produces normal GitHub review objects.

To switch, connect the replacement service to the repository and configure its native triggers first. In a dedicated change, set `provider.id`, `provider.adapter`, `provider.login` and the verified numeric `provider.user_id`. Use a GitHub API user/review response to verify identity. Disable the old native automatic trigger when cutting over; changing this JSON cannot disable an external service. Validate one positive finding, a clean control, a new push, a dismissed result and unavailable service before broader use. Do not run two full automatic reviewers indefinitely by default.

For a service without standard GitHub review objects, add a small adapter returning the same observation fields and tests for its documented output. Keep networking in the GET-only collector and never execute configurable shell commands. Do not guess finding counts or model details from text. Provider-specific parsing stays out of project rules and the workflow.

## Bootstrap another project

1. Copy this directory, `.github/review-pilot.json`, `.github/workflows/review-pilot.yml` and `scripts/tests/test_review_pilot.py` while retaining the directory layout. The only test dependency is PyYAML; integrate its test into the new project's shared checks.
2. Copy/adapt the [REVIEW template](../../docs/templates/REVIEW.template.md), link the project's contribution/architecture/testing procedures, and add two or three meaningful Code Review Rules to AGENTS.md. Set `policy_files` to the files actually present; replace iPhone-specific rules.
3. Configure one native reviewer and the expected bot identity. Keep `mode: advisory`. Repository identity comes from GitHub's environment or the local CLI argument, not a hard-coded project name.
4. Land the workflow on the trusted default branch, verify least-privilege permissions and keep it outside required checks. Test native review delivery plus automatic observation on a real PR and a later commit. Verify the summary/artifact names, statuses and source links.
5. Use the [pilot evaluation criteria](../../docs/code-review.md#rollout-and-evaluation) before replacing the service or tightening gates. Track finding disposition and human effort privately; the observer's booleans alone cannot calculate precision, recall or time saved. Artifacts expire after 30 days, so retain sanitized evaluation data locally when needed.

The provider's native posting is separate from this collector. For sensitive findings, follow the project's private disclosure route and review the provider's public-posting settings before enabling it on that project.
