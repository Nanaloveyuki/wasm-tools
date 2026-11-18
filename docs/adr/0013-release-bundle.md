# ADR 0013: Check the files actually shipped with a WASM release

Status: accepted. This records the bundle-check boundary and its verification gates; append new runtime support here when it is implemented.

## Problem

A valid WASM module can ship with a missing loader or worker, a stale compressed copy, or a loader that accidentally reads files from the source checkout. ABI and byte budgets cannot establish that these files form a usable release.

[moonsize](https://github.com/BigSaltyMan/moonsize) already covers detailed size analysis, budgets, gzip measurements, reference graphs and retained size. MoonHostABI owns Core ABI baselines and compatibility; Wasmoon supplies binary parsing and validation. Adding another implementation of those algorithms would repeat their responsibilities.

## Decision

Add `wsm bundle check MANIFEST`. An explicit versioned manifest lists publication paths, compressed-to-original relations, and Node ESM consumer entry points. MoonBit validates the manifest and reference closure, captures file bytes and SHA-256, evaluates findings and expected results, and writes JSON/Markdown reports. Node's standard zlib and JavaScript/WebAssembly runtime perform decompression and actual consumer execution. No compressor, ABI comparison, JS dependency parser or size-attribution engine is introduced.

Version 1 checks a directory, not an archive, npm packing rules or an OCI registry. The explicit root is resolved once and may point through a symlink. Below that resolved root, file paths must be portable relative paths and declared files must be regular files with no symlink at any path segment. Reports cannot replace the manifest or declared inputs and cannot target symlinks. Undeclared files are neither checked nor copied. The captured input limit is 64 MiB across at most 256 files.

Each encoded file names a declared identity source. Decode its captured bytes and compare the exact result against the captured original, including zero-length originals. Invalid streams and stale copies fail. Decoder output is bounded by the expected original length plus one byte; input left unconsumed by the decoder is rejected, including trailing padding.

Consumers import a declared `.mjs` entry, call a named export with JSON arguments and compare the JSON result against the manifest. Each consumer runs in its own fresh directory containing only captured declared files. Its child process has a deadline, limited output and no inherited Node preload/module-path configuration. This exposes undeclared dependencies and exercises actual WASM and Worker loading. Project code still has ordinary process filesystem and network access: this is process isolation, not an operating-system sandbox. Version 1 makes no browser-compatibility claim.

`requires` validates explicit references and is not an exhaustive dependency list: all declared files are copied for every consumer. Missing any declared file skips consumers while the capture findings fail the bundle. Arguments travel in a JSON request file rather than OS arguments. Results use a separate file, so logging JSON or exiting zero without a result cannot satisfy the check. The persisted JSON result is capped at 1 MiB; child stdout/stderr are capped at 1 MiB and each retained log is the first 4096 bytes. These are output limits, not a bound on consumer allocations or serialization peak memory.

The Linux Action accepts `command: bundle` with `mode: check`; its existing `command: release` default preserves check/prepare callers. It passes its own Node executable to the CLI and continues to publish per-invocation JSON/Markdown paths and status. It rejects preparation flags for bundles. CI pins Node 20 to verify the minimum supported runtime.

The publication-package focus is inspired by [publint](https://publint.dev/docs/); testing actual runtime behavior is informed by [wasm-pack test](https://github.com/wasm-bindgen/wasm-pack/blob/master/docs/src/commands/test.md). These are design references, not copied implementations or claims to reproduce all of their checks.

## Verification gates

1. Strict manifest parsing, file capture/hash and Core validation: exercise malformed references, missing files, nonregular paths, symlinks and output collisions.
2. gzip/Brotli equality: generate streams with standard codecs and remove or corrupt copies to establish failures.
3. Clean consumption: instantiate real WASM and start a real Worker; omit files that exist in the source tree, return wrong results and time out synchronous loops.
4. CLI/Action integration, full regression and documentation: use the real CLI, exercise both passing and deliberately failing jobs, update the proposal to match shipped behavior.

Proceed to each implementation gate only after the previous gate passes. Existing release checks remain available for artifact policies, processing and delegated ABI verification.

## Reference review, 2026-11-18

The current comparison is recorded in the root [README](../../README.md#独立贡献与生态分工), with fixed Wasmoon `2e98651`, moonsize `9499de8`, MoonHostABI `b2fcd60` and wasmslim `0.3.1` references. MoonHostABI already has real generated-adapter and isolated-install consumer tests; runtime testing itself is not a unique contribution. moonsize has whole-file gzip measurement and CI workflows plus a toolchain setup Action. The contribution here is checking relationships between the actual declared publication files and running configured ESM consumers from captured files, while delegating ABI and detailed size analysis.
