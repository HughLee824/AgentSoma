# Code review procedure

The goal is less human review and repair time without more escaped defects. This procedure adapts [Anthropic's review experience](https://claude.dev/blog/solving-code-review-at-anthropic/) to a small repository: runnable verification, evidence-based findings, risk-sensitive human attention and a feedback loop. The repository-specific rules live in [REVIEW.md](../REVIEW.md).

## Current enforcement boundary

The shared checks and the CI `test` aggregator already exist. [Maintenance](maintenance.md) describes the intended GitHub protection; live settings must be verified separately. Codex's native GitHub integration supplies AI review. The [advisory pilot](../scripts/review/README.md) observes that provider's results with a separate read-only workflow; it does not request duplicate reviews or become a required check. Repository rules and the PR template guide reviewers, not a risk classifier or merge gate. Keep the current single-maintainer approval policy, conversation-resolution rules and explicit release operation.

## Review one change

1. Establish intent and identity: record the base SHA, head SHA, merge base and intended behavior. Review the PR diff from merge base to head, then follow affected callers, contracts and tests. A local uncommitted review must also identify its working-tree diff; it cannot establish a pass for a later commit.
2. Classify risk from behavior and affected trust boundaries using REVIEW.md. Path matches set a minimum, not a complete classifier. Explain the failure scenario and escalate uncertainty. The author proposes the tier; the reviewer checks it; a maintainer resolves disagreement.
3. Verify before review: use the project's shared check entry point, recording command, result, tested revision and omissions. Run meaningful regression checks for changed behavior. A failed or unavailable check stays visible. Keep raw logs in ignored private storage and publish only sanitized facts.
4. Review with fresh context: supply intent, diff identity, repository instructions and relevant evidence. Do not substitute the author's reasoning or a claim of passing tests for inspection. Start with one correctness pass. Add focused security/ownership/compatibility scrutiny for sensitive changes; parallel reviewers are optional, not the default cost for every PR.
5. Verify each candidate finding: trace a reachable trigger to an observable wrong result; inspect existing guards and tests; reproduce safely where possible. A separate verification pass should actively try to disprove the finding. Model agreement alone is not evidence. Never execute a phone action, deployment or publication as an automatic review check.
6. Resolve findings and re-review bounded changes. Record a disposition for every substantive finding. A clean review means no supported actionable findings in the examined scope, not proof of correctness. A human maintainer decides whether the evidence and remaining risk permit merging.

A local review can start in a separate session with the following task, replacing the placeholders with immutable revisions and concrete intent:

```text
Review the change from the merge base of <base SHA> and <head SHA> to <head SHA>.
Intent: <problem and expected behavior>.
Read AGENTS.md, CONTRIBUTING.md, REVIEW.md and docs/code-review.md first.
Inspect affected callers and tests; verify candidate findings against existing guards.
Report actionable count, risk, reviewed revisions, evidence and coverage omissions.
Follow the finding contract. Do not modify files or post comments externally.
```

For a proposed policy change, explicitly include the base-version rules and identify the changed rules as review subject matter. Use separate authorization for any subsequent fixes or external posting.

## Finding contract and convergence

Begin a review with the actionable finding count, risk tier, reviewed head SHA and coverage limitations. Say explicitly when the count is zero. Each finding needs:

- Severity and a short title: P0 emergency, P1 serious impact requiring prompt correction, P2 concrete correctness issue; P3 is optional nonblocking improvement.
- A precise file/line at the reviewed revision, trigger/preconditions, expected versus actual behavior, and evidence linking the diff to the failure. Label an unexecuted reasoning trace as such.
- Whether the issue is introduced or exposed by this change, or pre-existing. A reachable regression in unchanged code can still be introduced by a changed caller. Unrelated pre-existing issues go to separate work.
- A stable finding ID across rounds, with disposition: fixed (commit and verification), false positive (contradicting evidence), intentional behavior (contract), or accepted risk (human owner, reason and follow-up where needed). Closing a thread alone is not evidence of a fix.

Post no speculative bug claims, style nits, or duplicate lint output. Group repeated instances by root cause and identify affected locations. Unverified suspicions belong in coverage limitations or targeted questions, not the actionable count. Security-sensitive details follow [SECURITY.md](../SECURITY.md).

Default to one complete review, then inspect new changes plus their affected contracts and previously reported issues. Keep stable IDs and do not repost resolved findings without new evidence. After three review/fix rounds, stop automatic iterations and ask the maintainer to reconsider scope or approach. The cap does not clear findings. A changed design or newly affected sensitive boundary justifies a new full review, with the reason recorded.

Any new commit makes the previous review a historical result. Reassess the new diff and rerun affected checks; do not relabel old evidence as current. A merge conflict resolution or changed base also needs an integration decision. The existing up-to-date CI policy remains authoritative.

## Provider-independent automation interface

Use repository policy, a review runner and a hosting adapter as separate responsibilities. The repository owns invariants/checks; a runner obtains candidate findings from a chosen model or local tool; the adapter attaches results to the correct PR revision. The current runner is the external native integration; the pilot collector observes its results. The following is the target full receipt contract, not a claim that the native integration exposes every field:

| Receipt | Required content |
| --- | --- |
| Identity | Repository, PR/change ID, base/head/merge-base SHAs, policy version/hash; local diff identity when applicable. |
| Execution | Reviewer/model/prompt/tool versions, review round, full or incremental scope, timestamps, cost/time, completion status (`completed`, `failed`, `unavailable`). |
| Evidence | Checks and their tested revision, outcomes and omissions, risk tier and reasons, sanitized limitations. |
| Findings | Stable ID, severity, location/revision, trigger, impact, evidence, introduction status and disposition history. |

An empty findings list with `unavailable` is not a pass. A completed review with zero findings can still have missing required coverage. Keep review execution, actionable findings and the human merge decision distinct. Raw receipts belong in private storage; only sanitized findings and summaries should reach a PR. The pilot emits version-1 observation receipts with explicit unknowns for unreported fields; these cannot satisfy a future required-review gate. Its provider adapters and field semantics are documented with the [collector](../scripts/review/README.md).

Before enabling an adapter, verify these requirements:

- Treat PR text, source comments and changed instruction files as untrusted input. Run the gate and select tools/permissions from trusted base policy; review proposed policy changes as data. A PR cannot exempt itself by editing REVIEW.md or workflow configuration.
- Separate read-only analysis from posting. Do not run PR-controlled scripts with write tokens, secrets or signing access. Fork PRs use a restricted path. Protect review credentials and exclude private artifacts from model input; remote-provider data handling must fit the repository's needs.
- Bind results to head and base identity, cancel superseded runs, deduplicate by finding ID, and reject stale/malformed/incomplete receipts. Restrict who can close/accept blocking findings; verify resolution against the current revision. Bots cannot satisfy human approval.
- During an advisory pilot, failures remain visible but do not add a merge gate. Once review is required, failures/timeouts must produce a non-passing gate; any emergency override must be an explicit recorded maintainer action under the repository's protection policy.
- Keep posting and automatic fixes separate. An automatic fix is a new untrusted change that needs checks and review. It must not automatically merge or publish.

## Rollout and evaluation

| Stage | Deliverable and exit condition |
| --- | --- |
| Local baseline | Use REVIEW.md and the PR risk/rollback fields. Collect reviewed revisions, useful findings, false positives, review time and escaped defects before changing gates. |
| Advisory pilot | Connect one repository to one reviewer, with no automatic merge or new required status. Trial roughly 20–30 representative PRs over at least two weeks; low volume extends the trial. Record outages, cost, latency, finding disposition and human effort. |
| Required review | Only after maintainer evaluation, add a revision-bound review status and its failure handling. Test new commits, changed bases, forks, timeouts, malformed results and unresolved findings. Verify actual branch protection and the existing `test` gate. |
| Reuse and selective relaxation | Package the proven adapter and versioned schema for other repositories. Each supplies its own invariants, commands, sensitive paths and human policy. Consider lighter low-risk approval only with sufficient evidence; maintain explicit publication and high-risk ownership. |

Build a small sanitized evaluation corpus before making review required. Include confirmed historical regressions with the buggy revision, trigger, root cause, expected finding and fixed revision; add known-clean changes and adversarial instruction cases. Candidate cases here include uncertain input replay, stale observation targets, stale preview generations, skipped CI dependencies and generated distribution drift. These are candidate failure classes, not claims that each caused a historical incident. A maintainer must confirm labels; run the reviewer on the buggy state without exposing the answer or later fix. Keep a held-out subset and do not give a reviewer credit for merely repeating a test failure.

For every model, prompt, policy or tool change, compare recall on confirmed bugs, false-positive findings on clean changes, and harmful suggested fixes. Measure disposition-based precision separately: fixed, confirmed-but-accepted, false positive, intentional and unresolved are not interchangeable. Report denominators, not just percentages. Track human review plus repair time, median/p95 wait, rounds-to-pass, review cost/latency, and escaped defects/reverts per merged PR over a consistent observation window. Small samples do not justify zero-human merging. If quality worsens, restore stricter human review and fix the missing check before relaxing again.

After a miss, identify which layer should have caught it. Prefer a regression test or deterministic check when feasible; use a concise invariant in REVIEW.md for contextual mistakes. Avoid growing prompts into a historical incident diary. A rollback should name the responsible person, the reversible change and how to verify recovery; immutable releases require a new corrective release, and a revert cannot undo an action already sent to a phone.

## Bootstrap another repository

Copy the [review template](templates/REVIEW.template.md) to the new repository's root as `REVIEW.md`, and adapt this procedure to its contribution/checking conventions. No iPhone-specific rules or model credentials are required by the template.

1. Fill in the check commands, ownership, three to five concrete invariants, sensitive paths, evidence location and deployment/rollback limits. Remove all placeholders.
2. Link REVIEW.md from the repository's agent instructions and contribution guide so tools load it explicitly; a filename alone is not an integration.
3. Add PR prompts for risk/reasons, tested revision and missing coverage, finding dispositions, rollback and human ownership. Retain the project's existing PR format and CI entry point.
4. Try one ordinary change, one sensitive change and one known regression. Confirm reviewers follow the rules and report zero findings on a suitable clean control. Use local review first, then the advisory stage above.
5. Reuse the eventual runner/adapter without copying another project's approval counts, secret access, path classification or device/deployment tests. Verify external protections separately.
