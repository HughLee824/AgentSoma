# Repository instructions

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing this repository. Use the existing architecture and shared checks; keep changes limited to the requested behavior.

For code review, read [REVIEW.md](REVIEW.md) for risk boundaries, evidence requirements and bounded re-review.

- Make reasonable reversible implementation decisions without repeated confirmation. Explain consequential assumptions and genuine blockers.
- Preserve unrelated changes. Keep current contracts, tests and generated plugin files consistent.
- Use `python3 scripts/check.py` for full device-free validation; select narrower checks only when justified by scope and report what was not run.
- Device acceptance is separate and explicit. Never replay uncertain phone input, expose private captures or treat host tests as physical-device evidence.
- Keep process reports and raw evidence in `.local/`; public docs describe durable behavior. Use the commit and PR conventions in CONTRIBUTING.md.

## Code Review Rules

- Preserve input uncertainty and target validity: never replay an action after uncertain dispatch or reuse stale observation/display identity. Safe path: report execution facts and require a fresh observation or explicit new action.
- Keep preview, recording and control ownership separate. Delayed frames must not survive revocation/replacement; cleanup must release only the caller's resources. Safe path: check owner and generation before applying asynchronous results.
- Preserve publication and CI trust boundaries: failed/skipped required checks cannot pass the `test` gate; ordinary merges cannot publish, and release artifacts remain immutable. Safe path: verify exact revisions and publish corrections as new releases.
