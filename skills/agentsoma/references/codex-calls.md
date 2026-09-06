# Fixed Codex call templates

Use these templates when `functions.exec` exposes `tools.exec_command` and `tools.write_stdin`. They run one command at a time; choose the next device action from its observed result. Other clients should use their native execution tool with the same completion discipline.

## Start a command

Change only the `argv` array for the intended CLI call. Every entry must be a string containing one literal argument. Keep the quoting expression and emit the full result, including `session_id` and `exit_code`.

```javascript
const argv = ["agentsoma", "devices"];
const cmd = argv.map(arg => "'" + arg.replace(/'/g, "'\\''") + "'").join(" ");
const result = await tools.exec_command({
  cmd,
  yield_time_ms: 10000,
  max_output_tokens: 6000
});
text(result);
```

For example, text replacement uses these arguments in the same template:

```json
["agentsoma", "--session", "SESSION_FROM_CONNECT", "type", "o4:e21", "--mode", "replace", "--text", "版本发布事项讨论"]
```

Use current session/reference values from actual results. Quotes, dollar signs, backticks, and spaces in user text stay literal under the template's shell quoting. Do not replace it with `JSON.stringify(argv)` as shell command text. Shell operators in the argument array are literal arguments, not pipelines; use the execution tool's supported stdin/file mechanism when `--stdin` is needed.

If a tool-level permission error or the CoreDevice diagnostic requires host execution, add the execution tool's supported `sandbox_permissions: "require_escalated"` and an appropriate `justification` to its options, following the active host policy and existing authorization. Do not treat that option as an AgentSoma CLI argument or request elevation speculatively.

## Continue the same command

When the result has a background `session_id`, use its actual numeric value below. This is **not** the AgentSoma session string. Repeat continuation only while the tool reports the same command is still running; consume each output chunk.

```javascript
const result = await tools.write_stdin({
  session_id: 12345,
  chars: "",
  yield_time_ms: 10000,
  max_output_tokens: 6000
});
text(result);
```

If `functions.exec` itself reports a running cell ID, resume that cell with its `wait` tool first. Do not re-execute the original script. Keep individual waits short enough to provide progress updates.

## Interpret completion

- A background handle or partial stdout is pending work, even if stdout already contains a CLI path or some JSON. Do not relaunch the command.
- An exit code means that shell process ended. Read its output and any AgentSoma `outcome` together; exit code zero does not establish the user's business result.
- `unknown` means input may have happened. Acquire a fresh observation before deciding what to do next. Do not use `action && observe` as an unconditional recovery template: a nonzero action exit can still need observation.
- A JavaScript syntax error before the execution tool was called did not reach AgentSoma. Correct the wrapper. Do not classify it as a device failure.
