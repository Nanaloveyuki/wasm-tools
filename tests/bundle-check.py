#!/usr/bin/env python3
"""Integration checks for `wsm bundle check`."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
WASM_CLI = ROOT / "_build/wasm/debug/build/wasm-tools.wasm"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def run(
    command: list[str],
    *,
    expected: int = 0,
    env: dict[str, str] | None = None,
    timeout: float = 20,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, text=True, capture_output=True, check=False, env=env, timeout=timeout)
    if result.returncode != expected:
        raise AssertionError(
            f"command exited {result.returncode}, expected {expected}: {command!r}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def manifest_for(*files: dict[str, object]) -> dict[str, object]:
    return {"format_version": 1, "files": list(files)}


def main() -> int:
    moonrun = shutil.which("moonrun")
    require(moonrun is not None, "moonrun is required to run the built wasm CLI")
    require(WASM_CLI.is_file(), f"built wasm CLI not found: {WASM_CLI}")
    node = shutil.which("node")
    require(node is not None, "Node 20+ is required to create compression fixtures")
    node_major = run([node, "--version"]).stdout.strip().removeprefix("v").split(".")[0]
    require(int(node_major) >= 20, f"Node 20+ is required to create compression fixtures, found {node_major}")

    with tempfile.TemporaryDirectory(prefix="wsm-bundle-check-") as temp:
        work = Path(temp)
        moonrun = str(moonrun)
        wat = work / "answer.wat"
        wasm = work / "answer.wasm"
        wat.write_text(
            '(module (func (export "answer") (result i32) i32.const 42))\n',
            encoding="utf-8",
        )
        run([moonrun, str(WASM_CLI), "--", "parse", str(wat), "-o", str(wasm)])
        wasm_bytes = wasm.read_bytes()

        def write_manifest(name: str, value: object) -> Path:
            path = work / f"{name}.json"
            path.write_text(json.dumps(value), encoding="utf-8")
            return path

        def write_bundle_manifest(name: str, *files: dict[str, object]) -> Path:
            value = manifest_for(*files)
            value["root"] = "bundle"
            return write_manifest(name, value)

        def invoke(
            manifest: Path,
            *,
            expected: int = 0,
            report_path: Path | None = None,
            summary_path: Path | None = None,
            node_path: str | None = None,
            env: dict[str, str] | None = None,
        ) -> tuple[subprocess.CompletedProcess[str], dict[str, object] | None]:
            report_path = report_path or work / f"{manifest.stem}.report.json"
            command = [moonrun, str(WASM_CLI), "--", "bundle", "check", str(manifest), "-o", str(report_path)]
            if summary_path is not None:
                command.extend(["--summary", str(summary_path)])
            if node_path is not None:
                command.extend(["--node", node_path])
            result = run(command, expected=expected, env=env)
            if expected == 2:
                return result, None
            if not report_path.exists():
                return result, None
            report = json.loads(report_path.read_text(encoding="utf-8"))
            require(report.get("format_version") == 1, "wrong bundle report version")
            require(report.get("mode") == "bundle-check", "wrong bundle report mode")
            return result, report

        def compress(source: Path, gzip_path: Path, brotli_path: Path) -> None:
            script = (
                "const fs = require('node:fs'); "
                "const zlib = require('node:zlib'); "
                "const input = fs.readFileSync(process.argv[1]); "
                "fs.writeFileSync(process.argv[2], zlib.gzipSync(input)); "
                "fs.writeFileSync(process.argv[3], zlib.brotliCompressSync(input));"
            )
            run([node, "-e", script, str(source), str(gzip_path), str(brotli_path)])

        def compression_manifest(name: str, *files: dict[str, object]) -> Path:
            value = manifest_for(*files)
            value["root"] = "bundle"
            return write_manifest(name, value)

        def consumer_manifest(
            name: str,
            files: list[dict[str, object]],
            consumers: list[dict[str, object]],
        ) -> Path:
            value: dict[str, object] = {
                "format_version": 1,
                "root": "bundle",
                "files": files,
                "consumers": consumers,
            }
            return write_manifest(name, value)

        # A real Core module and an ordinary asset produce a stable report and separate summary.
        bundle = work / "bundle"
        bundle.mkdir()
        (bundle / "app.wasm").write_bytes(wasm_bytes)
        asset_bytes = b"export const answer = 42;\n"
        (bundle / "index.mjs").write_bytes(asset_bytes)
        manifest = write_manifest(
            "valid",
            {
                **manifest_for({"path": "index.mjs"}, {"path": "app.wasm", "kind": "wasm"}),
                "root": "bundle",
            },
        )
        report_path = work / "valid.report.json"
        summary_path = work / "valid.summary.md"
        _, report = invoke(manifest, report_path=report_path, summary_path=summary_path)
        require(report is not None and report["status"] == "passed", "valid bundle should pass")
        require(report["manifest"] == str(manifest.resolve()), "report manifest path should be canonical")
        require(report["root"] == str(bundle.resolve()), "default root should be manifest directory")
        rows = report["files"]
        require([row["path"] for row in rows] == ["index.mjs", "app.wasm"], "file order/path mismatch")
        require(rows[0]["bytes"] == len(asset_bytes), "asset byte count mismatch")
        require(rows[0]["sha256"] == hashlib.sha256(asset_bytes).hexdigest(), "asset digest mismatch")
        require(rows[1]["bytes"] == len(wasm_bytes), "wasm byte count mismatch")
        require(rows[1]["sha256"] == hashlib.sha256(wasm_bytes).hexdigest(), "wasm digest mismatch")
        require(report["findings"] == [], "valid bundle should have no findings")
        require(report["compressions"] == [] and report["consumers"] == [], "optional report sections mismatch")
        require(summary_path.is_file(), "Markdown summary was not written")
        require(summary_path.read_text(encoding="utf-8").strip(), "Markdown summary is empty")

        app_gzip = bundle / "app.wasm.gz"
        app_brotli = bundle / "app.wasm.br"
        compress(wasm, app_gzip, app_brotli)
        compressed_manifest = compression_manifest(
            "compressed-valid",
            {"path": "app.wasm", "kind": "wasm"},
            {"path": "app.wasm.gz", "encoding": "gzip", "source": "app.wasm"},
            {"path": "app.wasm.br", "encoding": "br", "source": "app.wasm"},
        )
        _, report = invoke(compressed_manifest, node_path=node)
        require(report is not None and report["status"] == "passed", "valid gzip and Brotli bundle should pass")
        compressions = {row["path"]: row for row in report["compressions"]}
        for path, encoding in (("app.wasm.gz", "gzip"), ("app.wasm.br", "br")):
            row = compressions[path]
            require(row["source"] == "app.wasm", f"{path}: source mismatch")
            require(row["encoding"] == encoding, f"{path}: encoding mismatch")
            require(row["status"] == "passed", f"{path}: compression should pass")
            require(row["decoded_bytes"] == len(wasm_bytes), f"{path}: decoded size mismatch")
            require(
                row["decoded_sha256"] == hashlib.sha256(wasm_bytes).hexdigest(),
                f"{path}: decoded digest mismatch",
            )

        # Older valid modules fail when their bytes do not match the declared source.
        same_size_wat = work / "older-same-size.wat"
        same_size_wasm = work / "older-same-size.wasm"
        same_size_wat.write_text(
            '(module (func (export "answer") (result i32) i32.const 41))\n',
            encoding="utf-8",
        )
        run([moonrun, str(WASM_CLI), "--", "parse", str(same_size_wat), "-o", str(same_size_wasm)])
        same_size_bytes = same_size_wasm.read_bytes()
        require(len(same_size_bytes) == len(wasm_bytes), "same-size stale fixture should match raw byte length")
        longer_wat = work / "older-longer.wat"
        longer_wasm = work / "older-longer.wasm"
        longer_wat.write_text(
            '(module (func (export "answer_from_a_much_older_build") (result i32) i32.const 41))\n',
            encoding="utf-8",
        )
        run([moonrun, str(WASM_CLI), "--", "parse", str(longer_wat), "-o", str(longer_wasm)])
        longer_bytes = longer_wasm.read_bytes()
        require(len(longer_bytes) > len(wasm_bytes) + 1, "long stale fixture should exceed source by more than one byte")
        stale_same_gzip = work / "stale-same.gz"
        unused_brotli = work / "unused-same.br"
        compress(same_size_wasm, stale_same_gzip, unused_brotli)
        unused_gzip = work / "unused-long.gz"
        stale_long_brotli = work / "stale-long.br"
        compress(longer_wasm, unused_gzip, stale_long_brotli)
        (bundle / stale_same_gzip.name).write_bytes(stale_same_gzip.read_bytes())
        (bundle / stale_long_brotli.name).write_bytes(stale_long_brotli.read_bytes())
        stale_manifest = compression_manifest(
            "stale-compressed",
            {"path": "app.wasm", "kind": "wasm"},
            {"path": stale_same_gzip.name, "encoding": "gzip", "source": "app.wasm"},
            {"path": stale_long_brotli.name, "encoding": "br", "source": "app.wasm"},
        )
        _, report = invoke(stale_manifest, expected=1, node_path=node)
        require(report is not None and report["status"] == "failed", "stale compressed members should fail")
        stale_findings = report["findings"]
        require(
            any(
                finding.get("code") == "compression_mismatch"
                and finding.get("path") == stale_same_gzip.name
                for finding in stale_findings
            ),
            "same-size stale module should report compression_mismatch",
        )
        require(
            any(
                finding.get("code") in {"compression_mismatch", "compression_invalid"}
                and finding.get("path") == stale_long_brotli.name
                for finding in stale_findings
            ),
            "oversized stale module should report a compression failure",
        )

        # Corrupt streams and trailing Brotli bytes are rejected.
        (bundle / "corrupt.gz").write_bytes(b"not a gzip stream")
        (bundle / "corrupt.br").write_bytes(b"not a Brotli stream")
        (bundle / "trailing.br").write_bytes(app_brotli.read_bytes() + b"trailing bytes")
        corrupt_manifest = compression_manifest(
            "corrupt-compressed",
            {"path": "app.wasm", "kind": "wasm"},
            {"path": "corrupt.gz", "encoding": "gzip", "source": "app.wasm"},
            {"path": "corrupt.br", "encoding": "br", "source": "app.wasm"},
            {"path": "trailing.br", "encoding": "br", "source": "app.wasm"},
        )
        _, report = invoke(corrupt_manifest, expected=1, node_path=node)
        require(report is not None and report["status"] == "failed", "corrupt compressed members should fail")
        corrupt_compressions = {row["path"]: row for row in report["compressions"]}
        require(corrupt_compressions["corrupt.gz"]["status"] == "failed", "corrupt gzip should fail")
        require(corrupt_compressions["corrupt.br"]["status"] == "failed", "corrupt Brotli should fail")
        require(corrupt_compressions["trailing.br"]["status"] == "failed", "trailing Brotli bytes should fail")

        # Empty assets round-trip, while decompression output is bounded by its declared source.
        empty_source = bundle / "empty.txt"
        empty_source.write_bytes(b"")
        empty_gzip = bundle / "empty.txt.gz"
        empty_brotli = bundle / "empty.txt.br"
        compress(empty_source, empty_gzip, empty_brotli)
        empty_manifest = compression_manifest(
            "empty-compressed",
            {"path": "empty.txt"},
            {"path": "empty.txt.gz", "encoding": "gzip", "source": "empty.txt"},
            {"path": "empty.txt.br", "encoding": "br", "source": "empty.txt"},
        )
        _, report = invoke(empty_manifest, node_path=node)
        require(report is not None and report["status"] == "passed", "empty gzip/Brotli members should pass")
        require(all(row["decoded_bytes"] == 0 for row in report["compressions"]), "empty decoded size should be zero")

        tiny_source = bundle / "tiny.txt"
        tiny_source.write_bytes(b"x")
        large_input = work / "large-input.bin"
        large_input.write_bytes(b"z" * (1024 * 1024))
        unused_tiny_gzip = work / "tiny.gz"
        large_brotli = work / "large.br"
        compress(large_input, unused_tiny_gzip, large_brotli)
        (bundle / large_brotli.name).write_bytes(large_brotli.read_bytes())
        limit_manifest = compression_manifest(
            "compression-output-limit",
            {"path": "tiny.txt"},
            {"path": "large.br", "encoding": "br", "source": "tiny.txt"},
        )
        _, report = invoke(limit_manifest, expected=1, node_path=node)
        require(report is not None and report["status"] == "failed", "decompression output limit should fail")
        require(report["compressions"][0]["status"] == "failed", "over-limit decompression should fail its member")

        # Missing input members are skipped after file capture findings; Node is optional otherwise.
        missing_source_copy = bundle / "missing-source.wasm.gz"
        missing_source_copy.write_bytes(app_gzip.read_bytes())
        missing_inputs_manifest = compression_manifest(
            "missing-compressed-inputs",
            {"path": "missing-source.wasm", "kind": "wasm"},
            {"path": missing_source_copy.name, "encoding": "gzip", "source": "missing-source.wasm"},
            {"path": "app.wasm", "kind": "wasm"},
            {"path": "absent-copy.br", "encoding": "br", "source": "app.wasm"},
        )
        _, report = invoke(missing_inputs_manifest, expected=1, node_path=node)
        require(report is not None and report["status"] == "failed", "missing compression members should fail")
        skipped = {row["path"]: row for row in report["compressions"] if row["status"] == "skipped"}
        require(missing_source_copy.name in skipped, "missing source should skip its compression check")
        require("absent-copy.br" in skipped, "missing compressed copy should be skipped")

        absent_node = str(work / "no-such-node")
        missing_node_report = work / "missing-node.report.json"
        invoke(
            compressed_manifest,
            expected=2,
            report_path=missing_node_report,
            node_path=absent_node,
        )
        require(not missing_node_report.exists(), "missing Node should fail before writing a report")
        no_compression_manifest = write_bundle_manifest("no-node-needed", {"path": "index.mjs"})
        _, report = invoke(no_compression_manifest, node_path=absent_node)
        require(report is not None and report["status"] == "passed", "uncompressed bundles should not need Node")

        # Consumers execute from a fresh snapshot containing only the declared bundle files.
        (bundle / "loader.mjs").write_text(
            "import { readFile } from 'node:fs/promises';\n"
            "import { Worker } from 'node:worker_threads';\n"
            "export async function run(multiplier) {\n"
            "  const bytes = await readFile(new URL('./app.wasm', import.meta.url));\n"
            "  const { instance } = await WebAssembly.instantiate(bytes);\n"
            "  const direct = instance.exports.answer();\n"
            "  const worker = await new Promise((resolve, reject) => {\n"
            "    const thread = new Worker(new URL('./worker.mjs', import.meta.url), { workerData: bytes });\n"
            "    thread.once('message', resolve);\n"
            "    thread.once('error', reject);\n"
            "  });\n"
            "  return { direct, worker, scaled: direct * multiplier };\n"
            "}\n",
            encoding="utf-8",
        )
        (bundle / "worker.mjs").write_text(
            "import { parentPort, workerData } from 'node:worker_threads';\n"
            "const { instance } = await WebAssembly.instantiate(workerData);\n"
            "parentPort.postMessage(instance.exports.answer());\n",
            encoding="utf-8",
        )
        (bundle / "stateful.mjs").write_text(
            "import { existsSync, writeFileSync } from 'node:fs';\n"
            "export function run() {\n"
            "  const marker = new URL('./written-by-consumer', import.meta.url);\n"
            "  const existed = existsSync(marker);\n"
            "  writeFileSync(marker, 'seen');\n"
            "  return { existed };\n"
            "}\n",
            encoding="utf-8",
        )
        expected_consumer_value = {"scaled": 126, "worker": 42, "direct": 42}
        baseline_consumers = [
            {
                "name": "wasm-worker",
                "entry": "loader.mjs",
                "requires": ["app.wasm", "worker.mjs"],
                "export": "run",
                "args": [3],
                "expected": expected_consumer_value,
            },
            {
                "name": "wasm-worker-no-requires",
                "entry": "loader.mjs",
                "export": "run",
                "args": [3],
                "expected": expected_consumer_value,
            },
            *[
                {
                    "name": name,
                    "entry": "stateful.mjs",
                    "requires": [],
                    "export": "run",
                    "args": [],
                    "expected": {"existed": False},
                }
                for name in ("snapshot-one", "snapshot-two")
            ],
        ]
        baseline_consumer_manifest = consumer_manifest(
            "consumer-baseline",
            [
                {"path": "app.wasm", "kind": "wasm"},
                {"path": "loader.mjs"},
                {"path": "worker.mjs"},
                {"path": "stateful.mjs"},
            ],
            baseline_consumers,
        )
        _, report = invoke(baseline_consumer_manifest, node_path=node)
        require(report is not None and report["status"] == "passed", "real WASM consumer should pass")
        consumer_rows = {row["name"]: row for row in report["consumers"]}
        require(len(consumer_rows) == 4, "each configured consumer should have a report row")
        require(all(row["status"] == "passed" for row in consumer_rows.values()), "all baseline consumers should pass")
        require(consumer_rows["wasm-worker"]["actual"] == {"direct": 42, "worker": 42, "scaled": 126}, "consumer result mismatch")
        require(
            consumer_rows["wasm-worker-no-requires"]["actual"] == {"direct": 42, "worker": 42, "scaled": 126},
            "consumer should see declared files when requires is omitted",
        )

        poison = work / "poison.cjs"
        poison.write_text("process.on('beforeExit', () => { process.exitCode = 73; });\n", encoding="utf-8")
        poisoned_env = os.environ.copy()
        poisoned_env["NODE_OPTIONS"] = f"--require={poison}"
        poisoned_env["NODE_PATH"] = str(work)
        _, report = invoke(baseline_consumer_manifest, node_path=node, env=poisoned_env)
        require(report is not None and report["status"] == "passed", "consumer Node environment should ignore host Node overrides")

        # Files left in the source directory cannot leak into a declared-only consumer snapshot.
        for name, omitted, requires in (
            ("worker-not-declared", "worker.mjs", ["app.wasm"]),
            ("wasm-not-declared", "app.wasm", ["worker.mjs"]),
        ):
            files = [{"path": "loader.mjs"}]
            if omitted != "worker.mjs":
                files.append({"path": "worker.mjs"})
            if omitted != "app.wasm":
                files.append({"path": "app.wasm", "kind": "wasm"})
            consumer = {
                "name": name,
                "entry": "loader.mjs",
                "requires": requires,
                "export": "run",
                "args": [1],
                "expected": {"direct": 42, "worker": 42, "scaled": 42},
            }
            manifest = consumer_manifest(name, files, [consumer])
            _, report = invoke(manifest, expected=1, node_path=node)
            require(report is not None and report["status"] == "failed", f"{name}: omitted dependency should fail")
            require(report["consumers"][0]["status"] == "failed", f"{name}: consumer should execute and fail")
            require(
                any(finding.get("code") == "consumer_runtime" for finding in report["findings"]),
                f"{name}: missing snapshot dependency should be a runtime finding",
            )

        (bundle / "needs-file.mjs").write_text(
            "export function run() { return { ok: true }; }\n",
            encoding="utf-8",
        )
        missing_declared_consumer = consumer_manifest(
            "consumer-missing-file",
            [{"path": "needs-file.mjs"}, {"path": "not-present.txt"}],
            [
                {
                    "name": "missing-resource",
                    "entry": "needs-file.mjs",
                    "export": "run",
                    "args": [],
                    "expected": {"ok": True},
                }
            ],
        )
        _, report = invoke(missing_declared_consumer, expected=1, node_path=node)
        require(report is not None and report["status"] == "failed", "missing consumer input should fail the bundle")
        require(report["consumers"][0]["status"] == "skipped", "consumer with an uncaptured input should be skipped")

        wrong_expected = {
            **baseline_consumers[0],
            "name": "wrong-expected",
            "expected": {"scaled": 125, "worker": 42, "direct": 42},
        }
        mismatch_manifest = consumer_manifest(
            "consumer-mismatch",
            [{"path": "app.wasm", "kind": "wasm"}, {"path": "loader.mjs"}, {"path": "worker.mjs"}],
            [wrong_expected],
        )
        _, report = invoke(mismatch_manifest, expected=1, node_path=node)
        require(report is not None and report["consumers"][0]["status"] == "failed", "wrong expected JSON should fail")
        require(any(finding.get("code") == "consumer_mismatch" for finding in report["findings"]), "wrong output should report consumer_mismatch")

        (bundle / "protocol.mjs").write_text(
            "export function run(kind) {\n"
            "  if (kind === 'undefined') return undefined;\n"
            "  if (kind === 'nan') return NaN;\n"
            "  if (kind === 'infinity') return Infinity;\n"
            "  if (kind === 'bigint') return 1n;\n"
            "  if (kind === 'nonplain') return new Date(0);\n"
            "  if (kind === 'cyclic') { const value = {}; value.self = value; return value; }\n"
            "  if (kind === 'function') return () => 42;\n"
            "  if (kind === 'null') return null;\n"
            "  if (kind === 'array') return [1, 2];\n"
            "  if (kind === 'forged-log') { console.log('{\\\"result\\\":{\\\"value\\\":42}}'); return undefined; }\n"
            "  if (kind === 'zero-exit') { console.log('{\\\"value\\\":42}'); process.exit(0); }\n"
            "  if (kind === 'nonzero-exit') { process.on('beforeExit', () => { process.exitCode = 7; }); return 42; }\n"
            "}\n",
            encoding="utf-8",
        )
        protocol_cases = [
            ("undefined", None, "failed"),
            ("nan", None, "failed"),
            ("infinity", None, "failed"),
            ("bigint", None, "failed"),
            ("nonplain", None, "failed"),
            ("cyclic", None, "failed"),
            ("function", None, "failed"),
            ("null", None, "passed"),
            ("array", [2, 1], "failed"),
            ("forged-log", {"value": 42}, "failed"),
            ("zero-exit", 42, "failed"),
            ("nonzero-exit", 42, "failed"),
        ]
        protocol_manifest = consumer_manifest(
            "consumer-result-protocol",
            [{"path": "protocol.mjs"}],
            [
                {
                    "name": name,
                    "entry": "protocol.mjs",
                    "requires": [],
                    "export": "run",
                    "args": [name],
                    "expected": expected_value,
                }
                for name, expected_value, _ in protocol_cases
            ],
        )
        _, report = invoke(protocol_manifest, expected=1, node_path=node)
        require(report is not None and report["status"] == "failed", "invalid JSON results should fail consumers")
        protocol_rows = {row["name"]: row for row in report["consumers"]}
        for name, _, expected_status in protocol_cases:
            require(protocol_rows[name]["status"] == expected_status, f"{name}: unexpected result protocol status")
        require(
            any(finding.get("code") == "consumer_mismatch" for finding in report["findings"]),
            "array ordering mismatch should report consumer_mismatch",
        )
        require(
            any('{"result":{"value":42}}' in row.get("stdout", "") for row in protocol_rows.values()),
            "forged JSON stdout should be captured without becoming a result",
        )

        (bundle / "large-args.mjs").write_text(
            "export function run(value) { return { length: value.length }; }\n",
            encoding="utf-8",
        )
        (bundle / "large-result.mjs").write_text(
            "export function run() { return 'x'.repeat(1024 * 1024); }\n",
            encoding="utf-8",
        )
        large_args_manifest = consumer_manifest(
            "consumer-large-config",
            [{"path": "large-args.mjs"}, {"path": "large-result.mjs"}],
            [
                {
                    "name": "large-args",
                    "entry": "large-args.mjs",
                    "requires": [],
                    "export": "run",
                    "args": ["a" * 200_000],
                    "expected": {"length": 200_000},
                },
                {
                    "name": "large-result",
                    "entry": "large-result.mjs",
                    "requires": [],
                    "export": "run",
                    "args": [],
                    "expected": None,
                },
            ],
        )
        _, report = invoke(large_args_manifest, expected=1, node_path=node)
        require(report is not None and report["status"] == "failed", "oversized consumer result should fail the bundle")
        large_rows = {row["name"]: row for row in report["consumers"]}
        require(large_rows["large-args"]["status"] == "passed", "large arguments should survive config-file transport")
        require(large_rows["large-result"]["status"] == "failed", "over-limit result should fail its consumer")
        require(
            "consumer JSON result exceeds 1 MiB" in large_rows["large-result"]["stderr"],
            "over-limit result should be rejected before writing its result file",
        )

        (bundle / "throws.mjs").write_text(
            "export function run() { throw new Error('consumer boom'); }\n",
            encoding="utf-8",
        )
        (bundle / "hangs.mjs").write_text(
            "export function run(kind) {\n"
            "  if (kind === 'sync') { while (true) {} }\n"
            "  return new Promise(() => { setInterval(() => {}, 1000); });\n"
            "}\n",
            encoding="utf-8",
        )
        failure_manifest = consumer_manifest(
            "consumer-runtime-failures",
            [{"path": "throws.mjs"}, {"path": "hangs.mjs"}],
            [
                {
                    "name": "throws",
                    "entry": "throws.mjs",
                    "requires": [],
                    "export": "run",
                    "args": [],
                    "expected": None,
                },
                *[
                    {
                        "name": name,
                        "entry": "hangs.mjs",
                        "requires": [],
                        "export": "run",
                        "args": [kind],
                        "expected": None,
                        "timeout_ms": 200,
                    }
                    for name, kind in (("sync-timeout", "sync"), ("promise-timeout", "async"))
                ],
            ],
        )
        _, report = invoke(failure_manifest, expected=1, node_path=node)
        require(report is not None and report["status"] == "failed", "runtime errors and timeouts should fail consumers")
        failure_rows = {row["name"]: row for row in report["consumers"]}
        require(failure_rows["throws"]["status"] == "failed", "thrown consumer error should fail")
        require(failure_rows["sync-timeout"]["status"] == "failed", "synchronous consumer loop should time out")
        require(failure_rows["promise-timeout"]["status"] == "failed", "unresolved consumer promise should time out")
        require(
            any(finding.get("code") == "consumer_runtime" for finding in report["findings"]),
            "thrown consumer error should report consumer_runtime",
        )
        require(
            sum(finding.get("code") == "consumer_timeout" for finding in report["findings"]) >= 2,
            "both timeout cases should report consumer_timeout",
        )

        missing_consumer_node_report = work / "missing-consumer-node.report.json"
        invoke(
            baseline_consumer_manifest,
            expected=2,
            report_path=missing_consumer_node_report,
            node_path=absent_node,
        )
        require(not missing_consumer_node_report.exists(), "consumer check without Node should not write a report")

        default_root_manifest = write_manifest(
            "default-root",
            manifest_for({"path": "index.mjs"}),
        )
        (work / "index.mjs").write_bytes(asset_bytes)
        _, report = invoke(default_root_manifest)
        require(report is not None and report["status"] == "passed", "omitted root should use manifest directory")
        require(report["root"] == str(work.resolve()), "omitted root should resolve to manifest directory")

        root_link = work / "root-link"
        try:
            root_link.symlink_to(bundle, target_is_directory=True)
        except (NotImplementedError, OSError):
            pass
        else:
            linked_root_manifest = write_manifest(
                "linked-root",
                {"format_version": 1, "root": "root-link", "files": [{"path": "index.mjs"}]},
            )
            _, report = invoke(linked_root_manifest)
            require(report is not None and report["status"] == "passed", "explicit symlink root should resolve once")
            require(report["root"] == str(bundle.resolve()), "report root should be the canonical root target")

        # Missing files are reported together; invalid Core bytes fail their declared wasm entry.
        (bundle / "broken.wasm").write_bytes(b"not wasm")
        missing_and_invalid = write_bundle_manifest(
            "missing-and-invalid",
            {"path": "absent.js"},
            {"path": "broken.wasm", "kind": "wasm"},
            {"path": "another-absent.css"},
        )
        _, report = invoke(missing_and_invalid, expected=1)
        require(report is not None and report["status"] == "failed", "bad declared files need a failed report")
        require(len(report["files"]) == 3, "failed report should include every declared path")
        require(len(report["findings"]) >= 3, "missing and invalid files should be aggregated")

        # A child path beneath a regular file cannot resolve to a regular declared file.
        (bundle / "regular-parent").write_bytes(b"parent is a file")
        parent_file_manifest = write_bundle_manifest(
            "regular-parent",
            {"path": "regular-parent/child.txt"},
        )
        _, report = invoke(parent_file_manifest, expected=1)
        require(report is not None and report["status"] == "failed", "regular-file parent should fail")
        require(
            any(finding.get("path") == "regular-parent/child.txt" for finding in report["findings"]),
            "regular-file parent failure should identify its declared path",
        )

        # The capture limit is checked against file size before hashing or parsing contents.
        oversized = bundle / "oversized.bin"
        with oversized.open("wb") as stream:
            stream.truncate(64 * 1024 * 1024 + 1)
        require(oversized.stat().st_size == 64 * 1024 * 1024 + 1, "oversized fixture has wrong logical size")
        oversized_manifest = write_bundle_manifest("oversized", {"path": "oversized.bin"})
        _, report = invoke(oversized_manifest, expected=1)
        require(report is not None and report["status"] == "failed", "over-limit bundle should fail")
        require(
            any(finding.get("code") == "capture_limit" for finding in report["findings"]),
            "over-limit bundle should report capture_limit",
        )

        # Directories and symlinks are rejected, including a symlink in an ancestor segment.
        (bundle / "folder").mkdir()
        (bundle / "real.js").write_text("ok", encoding="utf-8")
        unsafe_paths = [{"path": "folder"}]
        try:
            (bundle / "final-link.js").symlink_to(bundle / "real.js")
            unsafe_paths.append({"path": "final-link.js"})
        except (NotImplementedError, OSError):
            pass
        outside = work / "outside"
        outside.mkdir()
        (outside / "nested.js").write_text("ok", encoding="utf-8")
        try:
            (bundle / "linked-dir").symlink_to(outside, target_is_directory=True)
            unsafe_paths.append({"path": "linked-dir/nested.js"})
        except (NotImplementedError, OSError):
            pass
        path_manifest = write_bundle_manifest(
            "bad-path-types",
            *unsafe_paths,
        )
        _, report = invoke(path_manifest, expected=1)
        require(report is not None and report["status"] == "failed", "non-regular/symlink inputs should fail")
        require(len(report["findings"]) >= len(unsafe_paths), "all unsafe input paths should be reported")

        # Invalid manifest structure and non-portable/duplicate paths fail before creating a report.
        invalid_manifests = {
            "bad-version": {"format_version": 2, "files": []},
            "file-root": {
                "format_version": 1,
                "root": "bundle/regular-parent",
                "files": [{"path": "x"}],
            },
            "missing-root": {"format_version": 1, "root": "missing", "files": [{"path": "x"}]},
            "absolute-path": manifest_for({"path": "/etc/passwd"}),
            "parent-path": manifest_for({"path": "../outside.js"}),
            "backslash-path": manifest_for({"path": "dir\\index.js"}),
            "duplicate-path": manifest_for({"path": "same.js"}, {"path": "same.js"}),
            "unknown-kind": manifest_for({"path": "same.js", "kind": "directory"}),
        }
        for name, value in invalid_manifests.items():
            invalid_manifest = write_manifest(name, value)
            expected_report = work / f"{name}.report.json"
            invoke(invalid_manifest, expected=2, report_path=expected_report)
            require(not expected_report.exists(), f"{name}: invalid manifest must not produce a report")

        # JSON and Markdown outputs cannot replace the manifest or a declared input.
        protected_manifest = write_bundle_manifest("protected", {"path": "real.js"})
        original_manifest = protected_manifest.read_bytes()
        original_input = (bundle / "real.js").read_bytes()
        alias_dir = work / "alias"
        alias_dir.mkdir()
        manifest_alias = alias_dir / ".." / protected_manifest.name
        input_alias = bundle / ".." / "bundle" / "real.js"
        for output_path in (protected_manifest, manifest_alias, bundle / "real.js", input_alias):
            invoke(protected_manifest, expected=2, report_path=output_path)
            require(protected_manifest.read_bytes() == original_manifest, "report output replaced its manifest")
            require((bundle / "real.js").read_bytes() == original_input, "report output replaced a declared input")
        for summary_path in (protected_manifest, manifest_alias, bundle / "real.js", input_alias):
            collision_report = work / "protected-summary-check.json"
            invoke(
                protected_manifest,
                expected=2,
                report_path=collision_report,
                summary_path=summary_path,
            )
            require(not collision_report.exists(), "summary path collision should not write a JSON report")
            require(protected_manifest.read_bytes() == original_manifest, "summary output replaced its manifest")
            require((bundle / "real.js").read_bytes() == original_input, "summary output replaced a declared input")
        same_output = work / "same-output.json"
        invoke(
            protected_manifest,
            expected=2,
            report_path=same_output,
            summary_path=same_output,
        )
        require(not same_output.exists(), "JSON and Markdown outputs must not share a path")
        invoke(protected_manifest, expected=2, report_path=bundle)
        invoke(
            protected_manifest,
            expected=2,
            report_path=work / "root-collision.json",
            summary_path=bundle,
        )
        require(not (work / "root-collision.json").exists(), "root path collision should not write a JSON report")

        report_target = work / "report-target.json"
        report_link = work / "report-link.json"
        report_target_bytes = b"existing report target\n"
        report_target.write_bytes(report_target_bytes)
        try:
            report_link.symlink_to(report_target)
        except (NotImplementedError, OSError):
            pass
        else:
            invoke(protected_manifest, expected=2, report_path=report_link)
            require(report_link.is_symlink(), "report output symlink should remain untouched")
            require(report_target.read_bytes() == report_target_bytes, "report output symlink target should remain untouched")

        # A failed JSON destination rolls back a summary that had an older version.
        summary_to_restore = work / "restore-summary.md"
        original_summary = b"previous summary\n"
        summary_to_restore.write_bytes(original_summary)
        missing_report_parent = work / "missing-report-parent"
        invoke(
            protected_manifest,
            expected=2,
            report_path=missing_report_parent / "report.json",
            summary_path=summary_to_restore,
        )
        require(summary_to_restore.read_bytes() == original_summary, "failed report write should restore prior summary")
        require(not missing_report_parent.exists(), "failed report write should not create a missing parent")

        summary_target = work / "old-summary.md"
        summary_link = work / "summary-link.md"
        summary_target_bytes = b"previous summary through a link\n"
        summary_target.write_bytes(summary_target_bytes)
        try:
            summary_link.symlink_to(summary_target)
        except (NotImplementedError, OSError):
            pass
        else:
            missing_link_report_parent = work / "missing-link-report-parent"
            invoke(
                protected_manifest,
                expected=2,
                report_path=missing_link_report_parent / "report.json",
                summary_path=summary_link,
            )
            require(summary_link.is_symlink(), "summary output symlink should remain untouched")
            require(summary_target.read_bytes() == summary_target_bytes, "summary symlink target should remain untouched")
            require(not missing_link_report_parent.exists(), "symlink rejection should happen before JSON output")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
