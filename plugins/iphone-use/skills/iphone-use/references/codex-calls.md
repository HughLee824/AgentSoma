# Codex: call the CLI directly

Use the CLI path returned by preflight. Choose each command from the current device evidence. Call the shell tool directly; when it is exposed through `functions.exec`, a thin invocation is enough:

```javascript
text(await tools.exec_command({
  cmd: "'/ABSOLUTE/CLI/FROM/PREFLIGHT' devices",
  sandbox_permissions: "require_escalated",
  justification: "Allow host CoreDevice access for this authorized iPhone task.",
  yield_time_ms: 10000,
  max_output_tokens: 6000
}));
```

The permissions above apply to a known restricted environment: request approved host execution before the first device command to avoid the CoreDevice sandbox timeout. An unrestricted environment keeps its existing context. Every command remains subject to approval; never bypass a rejection. Keep the selected CLI and execution context through disconnect. Local preflight and file reads need no device permissions. Use a normal wait (for example 10000 ms) for ordinary commands, so brief actions can finish without an extra polling turn. Use a short wait (for example 1000 ms) for connect/setup progress so authorization messages remain visible.

Do not generate a JavaScript runner, reusable function, `eval`/`store` wrapper, JSON parser or custom polling loop. The CLI already returns execution facts. Read them directly. Invoke `connect --device DEVICE_ID --reuse --progress`, then the chosen session command, for example:

```sh
'/ABSOLUTE/CLI/FROM/PREFLIGHT' --session SESSION tap o1:e2 --observe --agent-output
```

Quote literal shell arguments correctly, especially text containing dollar signs, quotes or newlines. Use supported `--stdin` with a quoted here-document for complex text if helpful. Do not use `action && observe`: a nonzero action can still have a usable attached observation.

## Evidence only when requested

When preflight advertises native evidence, append `--evidence-dir` to connect and session commands. The CLI saves its final full receipt and any returned screenshot/snapshot in a unique private subdirectory, before returning:

```sh
'/ABSOLUTE/CLI/FROM/PREFLIGHT' --session SESSION tap o1:e2 --observe --agent-output --evidence-dir '/REQUESTED/EVIDENCE/DIRECTORY'
```

Use the same flag for connect/disconnect to retain mode and ownership receipts. `artifacts` contains durable paths; use them directly. This archives the final JSON response, not the progress stream. Keep `archiveErrors` separate from the action outcome and exit status. If copying fails, repair evidence without replaying input. Ordinary tasks can use the CLI alone.

For an older CLI without this capability, the bundled helper remains a fallback in the same shell invocation:

```sh
set -o pipefail
'/ABSOLUTE/CLI/FROM/PREFLIGHT' --session SESSION tap o1:e2 --observe --agent-output |
  python3 '/ABSOLUTE/SKILL/DIRECTORY/scripts/agent-output.py' --evidence '/REQUESTED/EVIDENCE/DIRECTORY'
```

This fallback requires zsh/bash `pipefail` to preserve CLI failures; it forwards progress and archives stdout as well. Do not combine it with native evidence or change the selected CLI just to gain archival.

## View the returned screenshot

After completion, inspect the returned screenshot using the host image tool before choosing the next action. Prefer `artifacts.screenshot` when archived, otherwise the successful observation's screenshot path. A path printed in terminal output is not a viewed image. If the image tool is exposed through `functions.exec`:

```javascript
image((await tools.view_image({path: "/RETURNED/SCREENSHOT/PATH.png"})).image_url);
```

Read the image even when the CLI exit is nonzero, provided the observation succeeded. If image loading fails, retry only the image read. Do not repeat the device command or take another screenshot solely to recover this image. The original execution facts remain in the shell result and, when requested, the archived full receipt.

## Pending execution

When the shell returns a numeric execution `session_id`, continue that handle with the host's wait/input tool and empty input. When `functions.exec` returns a cell ID, use `functions.wait`. These handles are not iPhone-use session IDs. Never restart a command because it is still running. Use short waits for connect progress and relay `requiresUserAction=true` promptly. For an example, see [continuation](codex-continuation.md) only if needed.

Keep earlier output chunks: a chunk is not a complete reply. Wait for process completion, then distinguish action outcome, observation success and task success. Partial or unknown execution never authorizes replay.

When preview is requested/defaulted, read [live preview](live-preview.md). If preview was declined, skip both startup and that reference. Read [access recovery](access-recovery.md) only for an actual access failure; normal execution needs no additional adapter references.
