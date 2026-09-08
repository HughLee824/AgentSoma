# Public access release

The public entry point is [the AgentSoma website](https://agentsoma.rich-spool-5142.chatgpt.site). Its install flow uses the existing public Homebrew Tap and this repository's two Git marketplaces. The website is static; the plugin packages a skill, not an MCP service.

## Source ownership

| Source | Purpose |
| --- | --- |
| `website/` | Static site source, local fonts and reviewed demo media. |
| `website/.openai/hosting.json` | Sites project ID and static output directory. No credentials. |
| `skills/agentsoma/` | Canonical shared operation rules, client adapters and preflight. |
| `plugins/agentsoma/` | Self-contained dual-client distribution; committed copies checked by CI. |
| `.agents/plugins/marketplace.json` | Codex repository marketplace. |
| `.claude-plugin/marketplace.json` | Claude Code repository marketplace. |
| `docs/first-task.md` / `docs/plugins.md` | English first-task path and Chinese plugin guide. |

## Validate changes

```sh
swift test
python3 -m unittest discover -s scripts/tests -v
node --test scripts/tests/test_agent_templates.mjs
python3 scripts/sync-plugin.py --check
python3 scripts/sync-plugin.py --archive .build/plugins
python3 website/build.py
xcodebuild build-for-testing \
  -project Runner/AgentSomaRunner.xcodeproj -scheme AgentSomaRunner \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath .build/ci-runner \
  CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=17.0
```

The CI workflow runs Swift/Python checks, the unsigned Runner build, Node templates, public installation/bundle/link checks and the website build on macOS. It uploads the static output and plugin ZIP/checksum for review. The release workflow applies the template and plugin checks to binary releases and attaches the plugin ZIP/checksum to its draft; downloaded plugin artifacts are compared with the exact source before creating the draft. Neither workflow has a physical iPhone or claims task acceptance.

## Publish a plugin change

1. Update the canonical skill, adapter or preflight. Bump the version in both plugin manifests and the SKILL.md workflow version whenever installed content changes.
2. Run `python3 scripts/sync-plugin.py` and the checks above. Inspect the diff and relocated ZIP contents, including local reference targets and license.
3. Publish the reviewed commit to this public repository. Retain the source commit used for acceptance.
4. From outside the checkout, add the **public repository** as the marketplace, install in each client, and confirm the cached version. Use [the documented commands](first-task.md#install-a-client-plugin).
5. Run the first task sequentially on the phone in each client. Verify a real image read, current references, a real navigation action, final screen state and cleanup. Exercise one safe rejection/refresh path. Record the actual task results, not only tool exit codes.
6. Update from the previous installed plugin, start a fresh session and confirm the new workflow content is loaded. Keep CLI upgrades distinct from plugin upgrades.

Do not silently change content under a published version. For the initial release, a controlled previous local package can verify cache refresh, but label that result as a local-to-public upgrade rather than claiming an older public release existed. Official-directory submissions are separate from this Git distribution.

## Publish the website

Use Sites with the existing project ID in `website/.openai/hosting.json`. The intended audience is **public**. Build `website/dist` from the validated source, preserving the exact source commit for the deployed version. Only the site source belongs in the Sites source repository; do not upload the parent Swift repository, `.local`, profiles or client logs. The Sites tooling stores short-lived credentials outside source files and Git configuration.

Save and deploy the built static version through Sites, then verify the exact HTTPS URL without an authenticated session. Check installation anchors, client selection, clipboard success/failure, keyboard navigation, and narrow layouts (320, 375, 414 and 768 CSS pixels) as well as desktop. Update the existing site rather than creating a new one for fixes. The CI static artifact is a review/build artifact; uploading it does not deploy the live site.

After deployment, follow the website's two client paths using the public install source. Keep the website's installation text, the English first-task guide, Chinese plugin guide and both READMEs aligned.

## Evidence and rollback

Record date, public site URL, repository commit, plugin version, CLI/client versions, Mac/Xcode/iPhone/iOS versions, signing type, installation source, image-reading/tool evidence, task result, rejection/recovery, upgrade pickup, cleanup, and remaining limitations. Store raw client logs and device captures in ignored `.local/public-access/`. Publish only a deliberately sanitized acceptance summary and reviewed media under `website/assets/`.

If a public source or client task cannot be tested, state exactly what is blocked and leave that part unverified. A working Homebrew installation does not establish a fresh-Mac signing path. A successful local plugin install does not establish a public Git install. A build or deployment receipt does not establish two-client task success.

To roll back website content, redeploy an earlier validated Sites version. For a plugin regression, publish a **new patch version** with the corrected or reverted content so client caches refresh. Keep active device sessions disconnected while changing CLI/Runner installations. Reverting a source file without a version bump is not a reliable plugin rollback.
