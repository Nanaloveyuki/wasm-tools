import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const runAction = path.join(root, 'scripts/run-action.mjs');
const cliWasm = process.env.WSM_CLI_WASM || path.join(root, '_build/wasm/debug/build/wasm-tools.wasm');
const moonrun = process.env.MOONRUN || 'moonrun';

function decodeOutputs(text) {
  return Object.fromEntries(
    text
      .split(/\r?\n/)
      .filter(Boolean)
      .map((line) => {
        const separator = line.indexOf('=');
        return [line.slice(0, separator), line.slice(separator + 1)];
      }),
  );
}

function run(command, options = {}) {
  const result = spawnSync(command[0], command.slice(1), {
    encoding: 'utf8',
    shell: false,
    ...options,
  });
  if (result.error) throw result.error;
  return result;
}

function customSection(name, bytes) {
  const nameBytes = Buffer.from(name, 'utf8');
  const payload = Buffer.concat([Buffer.from([nameBytes.length]), nameBytes, bytes]);
  return Buffer.concat([Buffer.from([0, payload.length]), payload]);
}

async function main() {
  assert.ok(await readFile(cliWasm).then(() => true, () => false), `missing built wasm CLI: ${cliWasm}`);
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'wasm-tools-action-test-'));
  try {
    const workspace = path.join(tempRoot, 'workspace');
    const runnerTemp = path.join(tempRoot, 'runner-temp');
    await mkdir(workspace);
    await mkdir(runnerTemp);
    const watPath = path.join(workspace, 'module.wat');
    const wasmPath = path.join(workspace, 'module.wasm');
    await writeFile(watPath, '(module (func (export "run") (result i32) i32.const 1))\n');
    const parse = run([
      moonrun,
      cliWasm,
      '--',
      'parse',
      watPath,
      '-o',
      wasmPath,
    ]);
    assert.equal(parse.status, 0, `failed to create WAT fixture: ${parse.stderr}`);
    const original = await readFile(wasmPath);
    const marked = Buffer.concat([original, customSection('action-marker', Buffer.from('fixture'))]);
    const markedPath = path.join(workspace, 'marked.wasm');
    await writeFile(markedPath, marked);
    const stepSummary = path.join(tempRoot, 'step-summary.md');
    await writeFile(stepSummary, '');

    let serial = 0;
    async function invoke({ config, mode = 'check', outDir = '', wasmOpt = '' }) {
      serial += 1;
      const outputFile = path.join(tempRoot, `outputs-${serial}.txt`);
      await writeFile(outputFile, '');
      const env = {
        ...process.env,
        GITHUB_ACTION_PATH: root,
        GITHUB_WORKSPACE: workspace,
        RUNNER_TEMP: runnerTemp,
        GITHUB_OUTPUT: outputFile,
        GITHUB_STEP_SUMMARY: stepSummary,
        WSM_CLI_WASM: cliWasm,
        INPUT_CONFIG: config,
        INPUT_MODE: mode,
        INPUT_OUT_DIR: outDir,
        INPUT_MOONHOSTABI: 'moonhostabi',
        INPUT_WASM_OPT: wasmOpt,
      };
      const result = run([process.execPath, runAction], { cwd: workspace, env });
      return { result, outputs: outputFile };
    }

    const passConfig = path.join(workspace, 'pass.json');
    await writeFile(
      passConfig,
      JSON.stringify({
        format_version: 1,
        artifacts: [{ id: 'module', input: 'module.wasm', rules: {} }],
      }),
    );
    const pass = await invoke({ config: passConfig });
    assert.equal(pass.result.status, 0, `passing check failed: ${pass.result.stderr}`);
    const passOutputs = decodeOutputs(await readFile(pass.outputs, 'utf8'));
    const passReport = JSON.parse(await readFile(passOutputs['report-json'], 'utf8'));
    assert.equal(passReport.status, 'passed');
    assert.equal(passOutputs.status, 'passed');
    assert.ok(await readFile(passOutputs.summary, 'utf8'));
    assert.ok((await readFile(stepSummary, 'utf8')).length > 0, 'step summary was not appended');

    const failConfig = path.join(workspace, 'fail.json');
    await writeFile(
      failConfig,
      JSON.stringify({
        format_version: 1,
        artifacts: [{ id: 'module', input: 'module.wasm', rules: { max_bytes: 0 } }],
      }),
    );
    const failed = await invoke({ config: failConfig });
    assert.notEqual(failed.result.status, 0, 'rule violation did not fail the action runner');
    const failedOutputs = decodeOutputs(await readFile(failed.outputs, 'utf8'));
    const failedReport = JSON.parse(await readFile(failedOutputs['report-json'], 'utf8'));
    assert.equal(failedReport.status, 'failed');
    assert.equal(failedOutputs.status, 'failed');
    assert.notEqual(failedOutputs['report-json'], passOutputs['report-json'], 'invocations reused a stale report path');

    const prepareConfig = path.join(workspace, 'prepare.json');
    await writeFile(
      prepareConfig,
      JSON.stringify({
        format_version: 1,
        artifacts: [
          {
            id: 'prepared',
            input: 'marked.wasm',
            rules: { forbidden_custom_sections: ['action-marker'] },
            process: { strip_custom_sections: ['action-marker'] },
          },
        ],
      }),
    );
    const prepared = await invoke({ config: prepareConfig, mode: 'prepare' });
    assert.equal(prepared.result.status, 0, `prepare failed: ${prepared.result.stderr}`);
    const preparedOutputs = decodeOutputs(await readFile(prepared.outputs, 'utf8'));
    const preparedReport = JSON.parse(await readFile(preparedOutputs['report-json'], 'utf8'));
    const preparedWasm = path.join(preparedOutputs['prepared-dir'], 'prepared.wasm');
    const preparedBytes = await readFile(preparedWasm);
    const preparedHash = createHash('sha256').update(preparedBytes).digest('hex');
    assert.equal(preparedOutputs.status, 'passed');
    assert.equal(preparedReport.artifacts[0].after.sha256, preparedHash);
    assert.deepEqual(preparedBytes, original);

    const invalidConfig = path.join(workspace, 'invalid.json');
    await writeFile(invalidConfig, '{not-json');
    const invalid = await invoke({ config: invalidConfig });
    assert.notEqual(invalid.result.status, 0, 'invalid config did not fail');
    const invalidOutputs = decodeOutputs(await readFile(invalid.outputs, 'utf8'));
    assert.equal(invalidOutputs.status, 'error');
    assert.equal(invalidOutputs['report-json'], '', 'invalid config exposed a nonexistent report path');
    assert.match(await readFile(invalidOutputs.summary, 'utf8'), /invalid JSON/i);

    const badMode = await invoke({ config: passConfig, mode: 'deploy' });
    assert.notEqual(badMode.result.status, 0, 'invalid mode did not fail');
    const badModeOutputs = decodeOutputs(await readFile(badMode.outputs, 'utf8'));
    assert.equal(badModeOutputs.status, 'error');
    assert.equal(badModeOutputs['report-json'], '');
    assert.match(badMode.result.stderr, /mode must be check or prepare/);

    console.log('GitHub Action runner integration checks passed');
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
