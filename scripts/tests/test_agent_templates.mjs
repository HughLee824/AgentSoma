import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const root = new URL('../../', import.meta.url);
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
function blocks(path) {
  return [...readFileSync(new URL(path, root), 'utf8').matchAll(/```javascript\n([\s\S]*?)```/g)]
    .map(match => match[1]);
}
const [direct, imageRead] = blocks('skills/iphone-use/references/codex-calls.md');
const [resume] = blocks('skills/iphone-use/references/codex-continuation.md');
const [combined] = blocks('skills/iphone-use/references/action-observation.md');
const session = 'test-session';

test('Harness result capture preserves full JSON, stderr and nonzero status without replay', () => {
  const document = readFileSync(new URL('skills/iphone-use/references/deepseek-harness.md', root), 'utf8');
  const template = document.match(/```sh\n([\s\S]*?)```/)[1];
  const directory = mkdtempSync(join(tmpdir(), 'harness-result-test-'));
  try {
    const command = join(directory, 'iphone-use');
    writeFileSync(command, '#!/bin/sh\nprintf x >> "$TEST_CALLS"\ncat "$TEST_REPLY"\nprintf "fixture stderr\\n" >&2\nexit "$TEST_STATUS"\n', {mode: 0o700});
    for (const outcome of ['completed', 'not_dispatched', 'unknown']) {
      for (const observationOK of [true, false]) {
        const payload = {action: {outcome}, agentSummary: {outcome, comparison: {accepted: outcome === 'completed'}},
          observation: {ok: observationOK, result: {screenshot: '/fixture/current.png', text: '界面'.repeat(3000)}}};
        const json = JSON.stringify(payload);
        const replyPath = join(directory, 'fixture.json');
        const callsPath = join(directory, 'calls');
        writeFileSync(replyPath, json);
        writeFileSync(callsPath, '');
        const status = outcome === 'completed' ? 0 : 1;
        const execution = spawnSync('/bin/sh', ['-eu', '-c', template], {encoding: 'utf8', env: {
          ...process.env, PATH: `${directory}:${process.env.PATH}`, TMPDIR: directory,
          TEST_REPLY: replyPath, TEST_CALLS: callsPath, TEST_STATUS: String(status)
        }});
        assert.equal(execution.status, status);
        assert.equal(readFileSync(callsPath, 'utf8'), 'x');
        assert.equal(execution.stderr, 'fixture stderr\n');
        const savedPath = execution.stdout.match(/\niphone_use_result=(.+)\n$/)[1];
        assert.equal(execution.stdout.slice(0, json.length), json);
        assert.deepEqual(JSON.parse(readFileSync(savedPath, 'utf8')), payload);
        assert.equal(statSync(savedPath).mode & 0o777, 0o600);
      }
    }
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
});
const observed = {exit_code: 0, output: 'observation=o2 refs=current\nscreenshot="/fixture/screen.png"\n'};
function reply(outcome, fields = {}) {
  return {exit_code: outcome === 'completed' ? 0 : 1,
    output: JSON.stringify({session, ok: outcome === 'completed', outcome, ...fields})};
}

async function run(executions, continuations = [], action = ['tap', 'o1:e2']) {
  const calls = [];
  const output = [];
  async function next(queue, kind, options) {
    calls.push({kind, options});
    assert.ok(queue.length, `Unexpected ${kind}: possible command replay`);
    const result = queue.shift();
    if (result instanceof Error) throw result;
    return result;
  }
  const code = combined
    .replace('const session = "SESSION_FROM_CONNECT";', `const session = ${JSON.stringify(session)};`)
    .replace('const action = ["tap", "o1:e2"];', `const action = ${JSON.stringify(action)};`);
  await new AsyncFunction('tools', 'text', code)({
    exec_command: options => next(executions, 'exec', options),
    write_stdin: options => next(continuations, 'resume', options)
  }, value => output.push(value));
  assert.equal(executions.length, 0);
  assert.equal(continuations.length, 0);
  return {calls, output};
}

test('direct CLI example returns pending and failed results without replay or parsing', async () => {
  for (const result of [{session_id: 42, output: 'partial'},
    {exit_code: 1, output: '{"action":{"outcome":"unknown"}}'}]) {
    let calls = 0;
    const output = [];
    await new AsyncFunction('tools', 'text', direct)({exec_command: async options => {
      calls++;
      assert.equal(options.sandbox_permissions, 'require_escalated');
      return result;
    }}, value => output.push(value));
    assert.equal(calls, 1);
    assert.strictEqual(output[0], result);
  }
});

test('direct continuation polls once and exposes the chunk unchanged', async () => {
  const result = {exit_code: 1, output: 'remaining output'};
  let calls = 0;
  const output = [];
  await new AsyncFunction('tools', 'text', resume)({write_stdin: async options => {
    calls++;
    assert.equal(options.session_id, 12345);
    assert.equal(options.chars, '');
    return result;
  }}, value => output.push(value));
  assert.equal(calls, 1);
  assert.strictEqual(output[0], result);
});

test('direct image read never invokes a device command, including on read failure', async () => {
  const read = new AsyncFunction('tools', 'image', imageRead);
  const images = [];
  await read({view_image: async () => ({image_url: 'fixture'})}, value => images.push(value));
  assert.deepEqual(images, ['fixture']);
  await assert.rejects(read({view_image: async () => {throw Error('missing image');}},
    () => assert.fail()), /missing image/);
});

test('completed and unknown actions each get one new observation', async () => {
  for (const outcome of ['completed', 'unknown']) {
    const action = reply(outcome);
    const {calls, output} = await run([action, observed]);
    assert.deepEqual(calls.map(call => call.kind), ['exec', 'exec']);
    assert.ok(calls[0].options.cmd.includes("'tap' 'o1:e2'"));
    assert.equal(calls[1].options.cmd, "'iphone-use' '--session' 'test-session' 'observe'");
    assert.deepEqual(output, [{phase: 'action', execution: action}, {phase: 'observation', execution: observed}]);
  }
});

test('all supported input commands use literal arguments and the same session', async () => {
  for (const action of [['open', 'com.example.fixture'], ['swipe', 'o1:e2', '--direction', 'up'],
    ['type', 'o1:e2', '--mode', 'replace', '--text', "O'Brien $(printf WRONG)"],
    ['press', 'o1:e2', '--key', 'return']]) {
    const {calls} = await run([reply('completed'), observed], [], action);
    const literal = execFileSync('/bin/sh', ['-c', calls[0].options.cmd.replace("'iphone-use'", "'/usr/bin/printf' '%s\\0'")]);
    assert.deepEqual(literal.toString().split('\0').slice(0, -1), ['--session', session, ...action]);
  }
});

test('background chunks are accumulated before deciding whether to observe', async () => {
  const rejected = reply('not_dispatched');
  const {calls, output} = await run([{session_id: 42, output: rejected.output.slice(0, 12)}],
    [{session_id: 42, output: rejected.output.slice(12, 30)}, {...rejected, output: rejected.output.slice(30)}]);
  assert.deepEqual(calls.map(call => call.kind), ['exec', 'resume', 'resume']);
  assert.deepEqual(calls.slice(1).map(call => call.options.session_id), [42, 42]);
  assert.equal(output[0].execution.output, rejected.output);
  assert.equal(output[0].execution.exit_code, 1);
  assert.ok(output[1].skipped);
});

test('observation itself is continued without restarting either command', async () => {
  const {calls, output} = await run([reply('completed'), {session_id: 73, output: 'observation=o2 '}],
    [{exit_code: 0, output: 'refs=current\n'}]);
  assert.deepEqual(calls.map(call => call.kind), ['exec', 'exec', 'resume']);
  assert.equal(calls[2].options.session_id, 73);
  assert.equal(output[1].execution.output, 'observation=o2 refs=current\n');
});

test('confirmed rejection skips refresh unless the host requires observation', async () => {
  for (const requiresObservation of [undefined, false, true]) {
    const action = reply('not_dispatched', {requiresObservation});
    const {calls, output} = await run(requiresObservation ? [action, observed] : [action]);
    assert.equal(calls.length, requiresObservation ? 2 : 1);
    assert.deepEqual(output[0].execution, action);
    assert.equal(Boolean(output[1].execution), requiresObservation === true);
  }
});

test('unrecognized or mismatched replies cannot suppress observation or imply success', async () => {
  for (const action of [{exit_code: 1, output: 'truncated or invalid JSON'},
    {exit_code: 0, output: 'null'}, reply('not_dispatched', {session: 'other-session'}),
    reply('not_dispatched', {requiresObservation: 'invalid'})]) {
    const {calls, output} = await run([action, observed]);
    assert.equal(calls.length, 2);
    assert.deepEqual(output[0].execution, action);
  }
});

test('observation failures preserve the original action outcome and never replay input', async () => {
  for (const outcome of ['completed', 'unknown']) {
    for (const failure of [{exit_code: 1, output: '{"ok":false,"error":{"code":"capture_failed"}}'},
      new Error('observation execution tool unavailable')]) {
      const action = reply(outcome);
      const {calls, output} = await run([action, failure]);
      assert.equal(calls.length, 2);
      assert.deepEqual(output[0].execution, action);
      if (failure instanceof Error) assert.match(output[1].execution.toolError, /unavailable/);
      else assert.deepEqual(output[1].execution, failure);
    }
  }
});

test('uncertain command completion stops before observation and retains its handle', async () => {
  const {calls, output} = await run([{session_id: 42, output: 'partial'}], [new Error('continuation lost')]);
  assert.deepEqual(calls.map(call => call.kind), ['exec', 'resume']);
  assert.equal(output[0].execution.session_id, 42);
  assert.equal(output[0].execution.output, 'partial');
  assert.match(output[0].execution.toolError, /continuation lost/);
  assert.ok(output[1].skipped);
  for (const failure of [new Error('launch status unknown'), {output: 'no completion metadata'}]) {
    const stopped = await run([failure]);
    assert.equal(stopped.calls.length, 1);
    assert.ok(stopped.output[0].execution.toolError);
    assert.ok(stopped.output[1].skipped);
  }
});

test('unsupported operations fail before invoking a command', async () => {
  for (const action of [['disconnect'], ['setup'], [], ['tap', 42]]) {
    await assert.rejects(run([], [], action), /Supply a session/);
  }
});
