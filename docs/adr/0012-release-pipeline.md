# 0012 WASM release policies and GitHub Action

- Status: Accepted
- Date: 2026-11-18
- Supersedes: 0005 as the product direction; published contract commands retain their behavior.

## Context

Core ABI normalization, baselines and compatibility comparison overlap with MoonHostABI. Packaging another comparator as an Action would retain that overlap. Wasmoon `0.19.0` and its default branch `40379a3b7bde338ebb1dbbbb7822a7e3a92daab8` already provide validation, WAT conversion, WIT processing, runtime tests and substantial CI. That repository has four workflows, no Action metadata and no `workflow_call` entry point at the inspected commit. A shared CI entry point alone is insufficient independent value.

## Decision

- Make configurable release-artifact policies and processing the main product: byte and section budgets, growth budgets, exact import allowlists, custom-section requirements, final-output validation and batch reports. A reusable Action invokes the same MoonBit CLI and policy library as local users.
- Reuse `wasm_core` for parsing and validation. Restrict the initial release path to Core Wasm, including supported MoonBit `wasm` and `wasm-gc` artifacts. Do not claim recursive Component policy coverage.
- Delegate optional ABI checks exclusively to the native MoonHostABI CLI. The optional Action installer and integration tests pin `0.6.0`; caller-supplied executables are checked against the known report protocol, not a version string. Keep the original report, validate its known schema and artifact hash, and fail on errors or unknown results. The release path never falls back to the existing comparator. A subprocess avoids conflicting parser dependency versions.
- Preserve published `contract` APIs and commands as legacy utilities. Their normalization and comparison are no longer the independent contribution claimed for this product.
- Use strict, versioned JSON configuration. Reject duplicate keys, unknown fields, duplicate artifact identities, invalid budgets and contradictory section requirements. Import matching uses exact `(module, name)` pairs; no glob or regex language is introduced.
- `baseline` means an already published final Wasm file for growth comparison. `abi.baseline` means a MoonHostABI lock JSON; these have different formats and purposes. Neither baseline is transformed or updated automatically.
- Budget section sizes include section headers. Repeated labels are summed; custom sections use `custom:<exact name>`. Growth limits are inclusive; negative growth passes, and positive growth from a zero baseline fails a percentage limit. Integer cross-multiplication avoids percentage rounding.
- `check` validates existing final artifacts. `prepare` applies explicitly requested custom-section removal and optional `moon-wasm-opt`, then reruns the same validation and rules on the final bytes. Original and final facts remain visible. Static validation does not establish behavioral equivalence after optimization.
- Prepare into a new output directory only after every artifact passes. Reject existing output paths; never clean or replace them. Emit failures as reports without publishing partial artifacts. Paths in configuration are relative to its directory. Output names derive from restricted unique artifact IDs.
- The Action only handles installation, CLI execution, reports and outputs. Rule evaluation, comparison, processing and report generation remain in MoonBit. No hosted service, automatic baseline rewrite or PR commenting is required.

## Verification gates

1. **Check:** existing checks pass; strict configuration, inclusive budget boundaries, duplicate-section aggregation, missing baselines, import/custom rules and real MoonHostABI delegation are verified before processing is added.
2. **Prepare:** transformed bytes are validated and reevaluated; failures publish no output directory; existing files/directories are preserved; baseline files remain unchanged.
3. **Action:** batch outcomes, JSON/Markdown reports, action metadata and the actual runner command are tested end to end. Update README and proposal only after implemented behavior and limits are verified.

## Local verification (2026-11-18)

All three implementation gates passed before the proposal was updated. `moon check --target all --deny-warn` and `moon test --target all --deny-warn` passed (58 wasm tests and 25 tests each on wasm-gc, JS and native). Debug/release builds and the existing CLI smoke suite passed. Release integration exercised real MoonHostABI `0.6.0`, real `moon-wasm-opt`, batch failure, atomic publication, input aliases and restoration of an existing Markdown report after JSON output failure. The Action setup and runner were executed locally against a real MoonBit example (223 to 175 bytes, retaining `producers`). Node runner integration and actionlint `1.7.12` passed. GitHub-hosted execution remains a check for the pushed commit; these are local results.

## Sources

- [Wasmoon workflow](https://github.com/Milky2018/wasmoon/blob/40379a3b7bde338ebb1dbbbb7822a7e3a92daab8/.github/workflows/check.yml)
- [Wasmoon utility CLI](https://github.com/Milky2018/wasmoon/blob/40379a3b7bde338ebb1dbbbb7822a7e3a92daab8/modules/wasmoon/cmd/wasmoon-tools/main.mbt)
- [MoonHostABI CLI and protocol](https://github.com/0717lee/moonhostabi#cli-surface)
