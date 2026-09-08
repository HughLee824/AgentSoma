# Public access acceptance — 8 September 2026

The [public website](https://agentsoma.hughlee824.chatgpt.site), client marketplaces, installation guides and build checks are delivered. **The two-client physical iPhone task remains pending:** the device was unavailable and the user requested completing the remaining deliverables first.

## Published scope

| Item | Evidence |
| --- | --- |
| Repository implementation | `f14dcc86035c08fcc81ca23eda780641d3936bc6` on public `main`. |
| Website | Public HTTPS access verified without authentication; page, scripts, fonts and both reviewed images returned 200; an unknown path returned 404. |
| Website source | Sites version 2, source commit `bb4fb3cee7096cc68bfa7eaac800fec0d0f74fdf`, containing only the static site source. |
| Plugin | `agentsoma@agentsoma` version **0.1.2**, distributed from `HughLee824/AgentSoma` in both clients. |
| CLI | Existing public Homebrew **0.1.0**. No new CLI release was created for this stage. |
| CI | [Complete successful run](https://github.com/HughLee824/AgentSoma/actions/runs/34213017810): Swift, Python, Node, unsigned Runner build, plugin archive, website build and artifact upload. |

## Public client installation and upgrades

Both tests ran outside the source checkout. Each client registered the public Git repository as its marketplace, then updated its installed plugin. An initial controlled local **0.1.0 → public 0.1.1** transition was followed by a genuine **public 0.1.1 → public 0.1.2** upgrade. The local 0.1.0 test package was never described as an earlier public plugin release.

| Client | Fresh-session evidence |
| --- | --- |
| Codex CLI 0.146.0 | Loaded `~/.codex/plugins/cache/agentsoma/agentsoma/0.1.2/skills/agentsoma/SKILL.md`, reported workflow 0.1.2, read the Codex adapter and ran the bundled preflight successfully. |
| Claude Code 2.1.250 | Loaded `~/.claude/plugins/cache/agentsoma/agentsoma/0.1.2/skills/agentsoma/SKILL.md`, reported workflow 0.1.2, read the Claude adapter and ran the bundled preflight successfully. |

All nine files in each installed plugin matched the published package. Preflight found CLI 0.1.0, full Xcode and action `--observe` support. These sessions intentionally issued no device discovery, connection, setup or input commands.

The test Mac's Codex CLI could not parse its existing `features.context_management` table, and its configured GPT-6-Astra model required a newer CLI. The verification command used a temporary `features.context_management=false` override and GPT-5.5 at low reasoning effort. The global client configuration was preserved. This demonstrates plugin loading on that compatible test combination, not successful use of the incompatible default combination. Claude used its configured model and normal scoped tool permissions.

## Website and package verification

- Browser checks covered desktop and 320, 375, 414 and 768 CSS pixel layouts. Additional overflow checks covered 960, 1280 and 1920 pixels. Client tabs, arrow-key selection, install anchors and copy feedback worked.
- With JavaScript omitted, both client installation blocks remained visible. A local test fixture that rejected clipboard writes selected the exact command text and offered manual copying. The fixture was not deployed.
- Text and focus contrast were calculated. Fonts are served locally with their licenses. Real calculator captures are attributed to the separate CLI 0.1.0 verification on 7 September; they are not evidence of today's client task acceptance.
- Local checks passed: **97 Swift tests, 32 Python tests, 15 Node template tests**, unsigned Runner compilation, plugin/skill validators, relocatable reproducible ZIP checks and the static build.
- The downloaded CI artifact's SHA-256 matched GitHub's recorded digest. Its plugin ZIP/checksum and all 13 website files matched the validated local build byte for byte.

One [preceding CI run](https://github.com/HughLee824/AgentSoma/actions/runs/34212377831) failed two assertions in the existing CLI action/observation integration test. No CLI runtime code changed in this stage. A local 150-repeat run did not reproduce the failure; assertions were improved to include the actual response on future failures, and the subsequent complete CI run passed. The intermittent failure's root cause remains unconfirmed; no test retry or suppression was added.

The Draft release workflow now packages and verifies the plugin alongside future CLI releases. It was not dispatched to create another binary release during this stage.

## Remaining acceptance

When the phone is connected again, follow [the first-task guide](first-task.md#run-the-first-task) separately in Codex and Claude Code: discover the intended device, connect, discover/open Settings, read actual PNGs, navigate to General, verify the page, exercise a safe rejection/refresh path and disconnect with cleanup verified. Use the public installed plugin and preserve both successful and failed outcomes.

Fresh-Mac signing, free Personal Team provisioning/renewal and additional device/system combinations remain outside the verified scope. Raw client logs, device identifiers and local screenshots stay in ignored local evidence; no signing materials are part of the site or plugin.
