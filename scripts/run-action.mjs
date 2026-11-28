import { appendFile, mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const actionRoot = process.env.GITHUB_ACTION_PATH || path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const workspace = process.env.GITHUB_WORKSPACE || process.cwd();
const runnerTemp = process.env.RUNNER_TEMP || path.join(workspace, '.runner-temp');

function outputValue(name, value) {
  if (/[\r\n]/.test(value)) throw new Error(`output ${name} contains a newline`);
  return `${name}=${value}\n`;
}

async function writeOutputs(values) {
  const outputFile = process.env.GITHUB_OUTPUT;
  if (!outputFile) return;
  await appendFile(outputFile, values.map(([name, value]) => outputValue(name, value)).join(''));
}

async function appendStepSummary(summaryPath, fallback, diagnostic) {
  let text;
  try {
    text = await readFile(summaryPath, 'utf8');
  } catch {
    text = fallback;
    await writeFile(summaryPath, text, 'utf8');
  }
  if (diagnostic) {
    const safeMessage = markdownEscape(diagnostic);
    if (!text.includes(safeMessage)) {
      text += `${text.endsWith('\n') ? '' : '\n'}\nAction runner diagnostic:\n<pre>${safeMessage}</pre>\n`;
      await writeFile(summaryPath, text, 'utf8');
    }
  }
  const stepSummary = process.env.GITHUB_STEP_SUMMARY;
  if (stepSummary) await appendFile(stepSummary, text.endsWith('\n') ? text : `${text}\n`);
}

function markdownEscape(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('`', '&#96;')
    .replace(/\r\n?/g, '\n')
    .replaceAll('\n', '&#10;');
}

async function main() {
  await mkdir(runnerTemp, { recursive: true });
  const invocationDir = await mkdtemp(path.join(runnerTemp, 'wasm-tools-release-'));
  const reportPath = path.join(invocationDir, 'report.json');
  const summaryPath = path.join(invocationDir, 'summary.md');
  const configInput = process.env.INPUT_CONFIG || '';
  const mode = (process.env.INPUT_MODE || 'check').trim();
  const command = (process.env.INPUT_COMMAND || 'release').trim();
  const outInput = (process.env.INPUT_OUT_DIR || '').trim();
  const strictFilesInput = (process.env.INPUT_STRICT_FILES || 'false').trim();
  const npmArchiveInput = process.env.INPUT_NPM_ARCHIVE || '';
  const abiInput = process.env.INPUT_MOONHOSTABI || 'moonhostabi';
  const wasmOptInput = (process.env.INPUT_WASM_OPT || '').trim();
  const cliWasm = process.env.WSM_CLI_WASM || path.join(actionRoot, '_build/wasm/release/build/wasm-tools.wasm');

  let status = 'error';
  let preparedDir = '';
  let reportJson = '';
  let resultCode = 1;
  let diagnostic = '';

  try {
    if (!configInput) throw new Error('config is required');
    if (!['release', 'bundle'].includes(command)) throw new Error('command must be release or bundle');
    if (mode !== 'check' && mode !== 'prepare') throw new Error(`mode must be check or prepare; got ${mode}`);
    if (command === 'bundle' && mode !== 'check') throw new Error('bundle supports check mode only');
    if (command === 'bundle' && (outInput || wasmOptInput)) throw new Error('out-dir and wasm-opt require release prepare');
    if (mode === 'check' && outInput) throw new Error('out-dir is only valid in prepare mode');
    if (!['true', 'false'].includes(strictFilesInput)) throw new Error('strict-files must be true or false');
    if (command !== 'bundle' && (strictFilesInput === 'true' || npmArchiveInput)) {
      throw new Error('strict-files and npm-archive require bundle check');
    }

    const configPath = path.resolve(workspace, configInput);
    const args = [cliWasm, '--', command, mode, configPath, '-o', reportPath, '--summary', summaryPath];
    if (mode === 'prepare') {
      preparedDir = outInput ? path.resolve(workspace, outInput) : path.join(invocationDir, 'artifacts');
      args.push('--out-dir', preparedDir);
    }
    if (command === 'bundle') {
      args.push('--node', process.execPath);
      if (strictFilesInput === 'true') args.push('--strict-files');
      if (npmArchiveInput) args.push('--npm-archive', path.resolve(workspace, npmArchiveInput));
    } else {
      if (abiInput) args.push('--moonhostabi', abiInput);
      if (wasmOptInput) args.push('--wasm-opt', wasmOptInput);
    }

    const result = spawnSync(process.env.MOONRUN || 'moonrun', args, {
      cwd: workspace,
      env: process.env,
      encoding: 'utf8',
      shell: false,
      maxBuffer: 16 * 1024 * 1024,
    });
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    if (result.error) throw result.error;
    resultCode = result.status ?? 1;

    let report;
    try {
      report = JSON.parse(await readFile(reportPath, 'utf8'));
      reportJson = reportPath;
    } catch {
      diagnostic = result.stderr || result.stdout || `${command} ${mode} exited with code ${resultCode} without a JSON report`;
    }
    const expectedMode = command === 'bundle' ? 'bundle-check' : mode;
    if (report && report.format_version === 1 && report.mode === expectedMode && ['passed', 'failed', 'error'].includes(report.status)) {
      status = report.status;
    } else {
      status = 'error';
      if (report) diagnostic = 'CLI produced an unrecognized report schema or mode';
    }

    if (resultCode === 0 && (!report || status !== 'passed')) {
      resultCode = 1;
      if (!diagnostic) diagnostic = `${command} ${mode} exited successfully without a passed JSON report`;
    } else if (resultCode !== 0 && status === 'passed') {
      status = 'error';
      diagnostic ||= `${command} ${mode} exited with code ${resultCode} despite a passed report`;
    }

    if (resultCode === 0 && status === 'passed' && mode === 'prepare' && preparedDir) {
      try {
        const { stat } = await import('node:fs/promises');
        if ((await stat(preparedDir)).isDirectory()) {
          // Keep the prepared directory output only when the CLI reported success.
        } else {
          preparedDir = '';
          resultCode = 1;
          status = 'error';
          diagnostic = 'prepare reported success but did not create its output directory';
        }
      } catch {
        preparedDir = '';
        resultCode = 1;
        status = 'error';
        diagnostic = 'prepare reported success but did not create its output directory';
      }
    } else {
      preparedDir = '';
    }
  } catch (error) {
    resultCode = 1;
    status = 'error';
    diagnostic = error instanceof Error ? error.message : String(error);
    preparedDir = '';
    reportJson = '';
    process.stderr.write(`wasm-tools action: ${diagnostic}\n`);
  }

  const fallback = [
    '# WASM release gate',
    '',
    `Status: **${status}**`,
    '',
    diagnostic ? `<pre>${markdownEscape(diagnostic)}</pre>` : `Report: ${reportJson || reportPath}`,
    '',
  ].join('\n');
  await appendStepSummary(summaryPath, fallback, diagnostic);
  await writeOutputs([
    ['report-json', reportJson],
    ['summary', summaryPath],
    ['prepared-dir', preparedDir],
    ['status', status],
  ]);

  if (resultCode !== 0) process.exitCode = resultCode;
}

main().catch((error) => {
  process.stderr.write(`wasm-tools release action failed: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
