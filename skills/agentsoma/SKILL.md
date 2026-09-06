---
name: agentsoma
description: Operate apps on a connected physical iPhone using the AgentSoma CLI. Use when the user asks to use AgentSoma or perform an iPhone UI task. Does not cover desktop or browser automation, or development of AgentSoma itself.
---

# AgentSoma

Use the local `agentsoma` CLI for iPhone observation and input. The calling agent owns the user's task, UI interpretation, and outcome verification.

## Enter the right device session

- Start with `agentsoma devices`; use the device ID it returns. Desktop computer-use tools do not control this iPhone. Discover the app with `apps --query` using the user's app name, then use the returned bundle ID; do not guess a macOS bundle ID or substitute a similarly named app.
- For a new session, use `agentsoma connect --device DEVICE_ID`. Reuse an existing session only when it belongs to the current task and `status` confirms it is ready. Keep the returned AgentSoma session ID in subsequent calls.
- Follow `setup_required` / `setup_update_required` with the indicated `agentsoma setup --device DEVICE_ID`, using existing signing configuration, then connect again. Use a supplied signed `.xctestrun` for an explicitly chosen source workflow. Do not rebuild Runner or search signing directories for every task.
- A `coredevice_initialization_timeout` does not establish a disconnected phone. Follow its diagnostic: compare read-only device discovery once in an approved host execution context before repeating commands or restarting services. Keep the execution environment consistent once it works.

## Keep command completion visible

When using Codex's JavaScript tool orchestration, read [the fixed call templates](references/codex-calls.md) before the first command. They preserve execution metadata and quote literal arguments. With other execution tools, preserve the equivalent fields and use their continuation mechanism.

There are separate identities: the AgentSoma device session, the execution tool's background command ID, and (if present) the orchestration tool's running cell ID. A partial stdout result is not command completion. Retain the background ID and continue the original command until its exit code is available; do not start it again to obtain output.

## Observe, act, verify

1. Open the discovered app, then `observe`. Read the returned PNG with the available image tool and combine it with the AX text. Screenshot coordinates are pixels; action coordinates are `screen_points`.
2. If a target is omitted from compact output, use `inspect oN --query TEXT` or inspect a known subtree. This searches captured data only; `source_missing=true` cannot be repaired by paging the same snapshot. Use the screenshot to resolve ambiguous matches and geometry.
3. Perform one selected action with a current reference. Keep screen-guard defaults; `--max-screen-change` measures changes **before input**, relative to the observation, not the size of the expected animation or scroll. Change it only after understanding a concrete guard rejection.
4. After `completed` or `unknown`, observe again before another input. `completed` describes input completion, not task success. `unknown` may already have changed the app: inspect the result before deciding any further action, and do not automatically replay it. A `not_dispatched` error may still require a fresh observation; follow `requiresObservation` and reference validity.

`inspect` can read an invalidated cached observation, but cannot revive its references. An action screenshot contains no new AX references. A nonzero shell exit or lost transport response alone does not prove an input was never sent.

For an already authorized, selected action, use `--observe` when the installed command's `--help` lists it. Read `action.outcome` separately from `observation.ok`; top-level `ok` is true only when both succeed. A successful `observation.result` supplies fresh references, `text`, and `screenshot`, replacing a separate `observe`; read that PNG and verify the result before another input. If observation fails, retain the action facts and recover with observation, never by replaying input. This is a client-side sequence compatible with older hosts, not an exclusive device transaction. For older CLIs, read the [fallback template](references/action-observation.md); do not add `--observe` to that template's action array, which would duplicate capture.

## Adjust wheels from observed values

- Read the current selected value from the form or control and inspect the wheel's frame and child rows. Visible, enabled `text` is not a promise that tapping selects that value. If a value tap has no effect, prefer a controlled drag for similar wheels unless new evidence supports another interaction.
- `swipe oN:eN --direction up` moves the finger across 60% of the visible element height (width for horizontal movement). Slow velocity does not shorten that distance; this can cross several rows.
- Near the target, use explicit endpoints based on the observed row spacing: `swipe oN --from-x X --from-y Y --to-x X --to-y Y --velocity 100 --hold-duration 0.2`. These speed/hold values are starting points, not a one-row guarantee. Use the observation ID with endpoints; optionally add `--protect oN:eN` for an additional protected element.
- After each drag, read the actual value and adjust the remaining distance. Repeated no-change or overshoot calls for checking the selected field, frame, and interaction strategy before another attempt. Do not assume a minute-wheel wrap changes the hour or that changing the start preserves the intended end.
- A custom `scroll_view` is not a native `picker_wheel`. Do not invent a select-by-value CLI command. Use `agentsoma swipe --help` for supported parameters.

## Finish the user's task

Preserve the requested operation and object: creating an item does not authorize replacing a similar existing item. Before saving, verify the requested fields, including both dates, times, and timezone for a calendar task. Continue within existing authorization; ask only for missing consequential information or a required permission.

Give brief progress updates during longer work, including time spent recovering from errors. After saving, observe and verify the resulting UI before reporting success. Describe material app defaults when relevant. End the task's session with `disconnect` and check the cleanup result. Report unresolved execution or verification failures accurately.
