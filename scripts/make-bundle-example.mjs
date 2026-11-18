#!/usr/bin/env node

import { brotliCompressSync, gzipSync } from "node:zlib";
import { copyFileSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = dirname(scriptDir);
const defaultWasm = join(repoRoot, "_build/wasm/release/build/examples/examples.wasm");
const exampleDir = join(repoRoot, "examples/bundle");

function usage() {
  process.stdout.write(
    "Usage: node scripts/make-bundle-example.mjs OUTPUT_DIR [WASM_SOURCE]\n",
  );
}

function main(args) {
  if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
    usage();
    return;
  }
  if (args.length > 2 || args[0].startsWith("-")) {
    usage();
    process.exitCode = 2;
    return;
  }

  const major = Number.parseInt(process.versions.node.split(".")[0], 10);
  if (!Number.isInteger(major) || major < 20) {
    throw new Error("Node.js 20 or newer is required");
  }

  const outputDir = resolve(args[0]);
  const wasmSource = resolve(args[1] ?? defaultWasm);
  let ownsOutput = false;
  try {
    mkdirSync(outputDir);
    ownsOutput = true;

    const packageDir = join(outputDir, "package");
    mkdirSync(packageDir);
    const wasm = readFileSync(wasmSource);
    copyFileSync(join(exampleDir, "loader.mjs"), join(packageDir, "loader.mjs"));
    copyFileSync(join(exampleDir, "worker.mjs"), join(packageDir, "worker.mjs"));
    writeFileSync(join(packageDir, "calculator.wasm"), wasm, { flag: "wx" });
    writeFileSync(join(packageDir, "calculator.wasm.gz"), gzipSync(wasm), { flag: "wx" });
    writeFileSync(join(packageDir, "calculator.wasm.br"), brotliCompressSync(wasm), { flag: "wx" });

    const manifest = {
      format_version: 1,
      root: "package",
      files: [
        { path: "loader.mjs" },
        { path: "worker.mjs" },
        { path: "calculator.wasm", kind: "wasm" },
        { path: "calculator.wasm.gz", encoding: "gzip", source: "calculator.wasm" },
        { path: "calculator.wasm.br", encoding: "br", source: "calculator.wasm" },
      ],
      consumers: [
        {
          name: "node-worker",
          entry: "loader.mjs",
          requires: ["calculator.wasm", "worker.mjs"],
          export: "check",
          args: [20, 22],
          expected: { direct: 42, worker: 42 },
        },
      ],
    };
    writeFileSync(join(outputDir, "bundle.json"), `${JSON.stringify(manifest, null, 2)}\n`, { flag: "wx" });
    process.stdout.write(`Bundle example written: ${join(outputDir, "bundle.json")}\n`);
  } catch (error) {
    if (ownsOutput) rmSync(outputDir, { recursive: true, force: true });
    throw error;
  }
}

try {
  main(process.argv.slice(2));
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`make-bundle-example: ${message}\n`);
  process.exitCode = 1;
}
