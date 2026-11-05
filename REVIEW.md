# Review instructions

Read [CONTRIBUTING.md](CONTRIBUTING.md), the PR's intended behavior, and the relevant contracts in [architecture](docs/architecture.md) and [testing](docs/testing.md). Follow the [review procedure](docs/code-review.md) for evidence, finding disposition and bounded re-review. These instructions guide reviewers; the [advisory pilot](scripts/review/README.md) observes the existing AI service without changing GitHub protection.

## What failure looks like here

| Changed area | Review for |
| --- | --- |
| `Sources/IPhoneUseCore/{Actions,Session,Observation,Backends}/`, `Runner/`, `packages/runner-support/` | Wrong-device/field/display input, stale references, replay after uncertain dispatch, lost execution facts, automatic backend switching, incompatible CLI/Runner protocols. Follow the complete caller-to-backend path; an input receipt is not proof of the UI outcome. |
| `Sources/IPhoneUseCore/{Media,Device,Transport}/` | Ownership and cancellation races, stale asynchronous frames after replacement/revocation, unbounded buffering, cross-owner cleanup, preview pixels authorizing input, loopback/Host/Origin/capability checks weakened. Preview, recording and control have distinct lifetimes. |
| `Sources/IPhoneUseCore/Setup/`, `scripts/release/`, `scripts/plugin/`, `.github/`, `packaging/`, manifests and dependency pins | Untrusted code reaching credentials, unverified artifacts, skipped/failed checks satisfying the final gate, publishing the wrong revision, overwriting releases, signing or installation regressions. Ordinary merges must not publish. |
| `skills/iphone-use/`, `plugins/`, `packages/iphone-use-skill/` | Instructions that authorize unsafe input or misstate tool behavior; drift between canonical sources and generated distributions. Review source behavior first, then verify generated consistency. |
| Documentation and tests | Instructions that lie about supported behavior or validation; tests that accept the wrong outcome, require private evidence, or weaken an existing contract. |

Braces group alternative directories. Paths guide attention; inspect affected callers and shared helpers outside them too.

## Risk and verification

- High risk: changes to input dispatch/replay/target validity, device ownership, authentication/privacy, signing/installers, publication, CI permissions or required gates. Behavioral skill instructions affecting these boundaries also qualify. A prose-only change to these contracts still needs high-risk scrutiny.
- Medium risk: other runtime behavior, compatibility, dependency changes and preview lifecycle changes. Escalate when they cross a high-risk boundary.
- Low risk: demonstrably nonfunctional documentation, copy or test-only maintenance that leaves contracts and protections intact. Unknown impact starts at medium; an unresolved sensitive-boundary impact is high.

Use the existing shared checks; do not create a second check runner. Full device-free validation is `python3 scripts/check.py`. A justified narrower check must identify omitted coverage. Device-facing changes need affected-scope physical acceptance or an explicit unverified limitation and maintainer disposition; reviewers must never initiate phone input to obtain evidence.

The single-maintainer policy in CONTRIBUTING.md remains in force. A human maintainer owns merge and risk acceptance; an AI finding or clean review is not human approval. Seek independent review when available, especially at high risk. Without it, record the missing independent review, evidence, remaining risk and rollback decision; do not silently downgrade the risk.

Ignore `.local/`, build output, credentials and private captures as review inputs. Do not post them or feed them to an external reviewer. Skip hand-reviewing generated copies when source and consistency checks suffice; investigate any unexpected generated difference. Formatting and lint diagnostics belong to existing checks, not review comments.
