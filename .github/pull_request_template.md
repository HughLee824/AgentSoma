## Problem and behavior

Explain the concrete trigger, previous behavior and resulting behavior. Link the relevant issue if any.

## Validation

List checks actually run, results and skips. For device-facing changes, identify the CLI/Runner revision, device model and OS/toolchain, scenarios, outcomes and cleanup. Keep raw evidence private.

Identify the tested revision and distinguish local results from CI results. Explain omitted coverage.

## Risk and review

Choose low, medium or high using REVIEW.md. Explain the affected behavior/trust boundary, likely failure and remaining uncertainty. Identify the human maintainer responsible for the merge decision; record independent review or its absence for high-risk changes. Summarize substantive finding dispositions, or state that review has not run or found no actionable issues, with the reviewed revision and scope.

## Rollback

Explain how to undo or contain the change and verify recovery, including migration or irreversible side effects. Published artifacts remain immutable; use a new corrective release where required. For documentation-only changes, a commit revert is sufficient.

## Compatibility and limitations

Describe remaining risks, unverified cases and any upgrade steps. For an incompatible change, include `BREAKING CHANGE:` and use `!` in the PR title.

- [ ] The change has one coherent purpose and the title follows CONTRIBUTING.md.
- [ ] Tests and documentation cover the changed behavior; generated files are synchronized where applicable.
- [ ] Validation claims distinguish builds, automated tests and physical-device acceptance.
- [ ] The diff contains no credentials, device identifiers, private captures or process diaries.
