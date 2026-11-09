# Access recovery

Read for a concrete startup, setup or connection failure.

- During Runner startup, promptly relay `connection_progress` messages. A confirmed `requiresUserAction=true` means ask the user to complete **Enable UI Automation on the iPhone**, never in chat, and continue the same pending command. Without explicit evidence, phrase this conditionally; a slow start, timeout, unavailable log monitor or stopped video is not proof of authorization. Never switch modes or relaunch to avoid a prompt. See [connection progress](connection-progress.md).

- `setup_required` / `setup_update_required`: follow the indicated `setup --device DEVICE_ID` with existing signing configuration for the selected Runner route, then connect. When preflight reports setup preview, use `setup --progress --preview` (or `--progress --no-preview` for an explicit preview opt-out) and follow [setup progress](connection-progress.md#setup-verification). An explicit source workflow can use its supplied signed `.xctestrun`; do not search signing directories or rebuild routinely.
- `coredevice_initialization_timeout`: follow the diagnostic and compare read-only discovery **once** in an approved host execution context. It does not prove disconnection. Preserve the successful tool execution options for **connect and all subsequent device calls**, including disconnect; approval for one command does not automatically change later calls. The [Codex adapter](codex-calls.md) stores this context and describes a bounded startup correction. Do not switch to desktop discovery or reset services.
- Same failure and unchanged device state: stop retrying, report the concrete missing connection/unlock/trust/permission, and wait for new evidence. Do not use timed connect loops or `setup` to repair an unavailable tunnel unless instructed by the CLI.

If a start failed before returning a session ID, inspect this attempt’s startup/error/exit facts before starting another connection. No returned ID does not prove no host was created. Correct an evidenced pre-input setup or path issue once; stop on the same unchanged failure. Never use another execution mechanism to bypass a rejected approval.
