# Continue the existing command

Use the numeric execution `session_id` returned by the shell (not the phone session). Resume with empty input; read each new chunk together with the prior output. A thin host invocation is sufficient:

```javascript
text(await tools.write_stdin({
  session_id: 12345,
  chars: "",
  yield_time_ms: 1000,
  max_output_tokens: 6000
}));
```

Replace `12345` with the actual pending handle. If `functions.exec` itself yielded a cell ID, use `functions.wait` instead. Continue until an exit code exists. Relay authorization progress promptly; do not synthesize permission prompts from elapsed time.

Do not start another phone action while this command is unresolved. Never restart the command to recover output, and do not build a polling function or concatenate JSON in generated code. If a response was truncated, inspect the existing archived stdout when available. Otherwise report the missing execution facts without replaying the action.

After completion, read action and observation facts independently, including on nonzero exit. View the successful observation's returned screenshot with the host image tool as described in [direct calls](codex-calls.md). If only image loading fails, retry that file read; the command result remains authoritative about dispatch and uncertainty.
