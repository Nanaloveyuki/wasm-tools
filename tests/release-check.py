#!/usr/bin/env python3
"""Integration checks for `wsm release check` and `prepare`."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
WASM_CLI = ROOT / "_build/wasm/debug/build/wasm-tools.wasm"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def run(command: list[str], *, expected: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != expected:
        raise AssertionError(
            f"command exited {result.returncode}, expected {expected}: {command!r}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def encode_uleb(value: int) -> bytes:
    encoded = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        encoded.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(encoded)


def custom_section(name: str, data: bytes) -> bytes:
    name_bytes = name.encode("utf-8")
    payload = encode_uleb(len(name_bytes)) + name_bytes + data
    return b"\x00" + encode_uleb(len(payload)) + payload


def config_for(*artifacts: dict[str, Any]) -> dict[str, Any]:
    return {"format_version": 1, "artifacts": list(artifacts)}


def artifact(
    artifact_id: str,
    input_name: str,
    rules: dict[str, Any] | None = None,
    **extra: Any,
) -> dict[str, Any]:
    value: dict[str, Any] = {
        "id": artifact_id,
        "input": input_name,
        "rules": rules or {},
    }
    value.update(extra)
    return value


def main() -> int:
    moonrun = shutil.which("moonrun")
    require(moonrun is not None, "moonrun is required to run the built wasm CLI")
    require(WASM_CLI.is_file(), f"built wasm CLI not found: {WASM_CLI}")
    moonhostabi = os.environ.get("MOONHOSTABI") or shutil.which("moonhostabi")
    abi_available = bool(moonhostabi)
    moonhostabi = moonhostabi or "moonhostabi"

    with tempfile.TemporaryDirectory(prefix="wsm-release-check-") as temp:
        work = Path(temp)
        (work / "imported.wat").write_text(
            '(module (import "env" "log" (func (param i32))))\n',
            encoding="utf-8",
        )
        run(
            [
                moonrun,
                str(WASM_CLI),
                "--",
                "parse",
                str(work / "imported.wat"),
                "-o",
                str(work / "imported.wasm"),
            ]
        )
        base = (work / "imported.wasm").read_bytes()
        (work / "plain.wasm").write_bytes(base)

        first = custom_section("meta", b"ab")
        second = custom_section("meta", b"cde")
        decorated = base + first + second
        (work / "decorated.wasm").write_bytes(decorated)
        custom_total = len(first) + len(second)
        growth = len(decorated) - len(base)

        def check(
            name: str,
            value: dict[str, Any],
            expected_code: int = 0,
            *,
            raw: str | None = None,
            output_path: Path | None = None,
        ) -> tuple[dict[str, Any] | None, subprocess.CompletedProcess[str]]:
            config_path = work / f"{name}.json"
            report_path = output_path or work / f"{name}.report.json"
            if raw is None:
                config_path.write_text(json.dumps(value), encoding="utf-8")
            else:
                config_path.write_text(raw, encoding="utf-8")
            result = run(
                [
                    moonrun,
                    str(WASM_CLI),
                    "--",
                    "release",
                    "check",
                    str(config_path),
                    "-o",
                    str(report_path),
                    "--moonhostabi",
                    moonhostabi,
                ],
                expected=expected_code,
            )
            if report_path.exists():
                try:
                    report = json.loads(report_path.read_text(encoding="utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    return None, result
                require(report.get("format_version") == 1, f"{name}: wrong report version")
                require(report.get("mode") == "check", f"{name}: wrong report mode")
                return report, result
            return None, result

        def prepare(
            name: str,
            value: dict[str, Any],
            output_dir: Path,
            expected_code: int = 0,
            *,
            wasm_opt: str | None = None,
            summary_path: Path | None = None,
        ) -> tuple[dict[str, Any] | None, subprocess.CompletedProcess[str]]:
            config_path = work / f"{name}.json"
            report_path = work / f"{name}.report.json"
            config_path.write_text(json.dumps(value), encoding="utf-8")
            command = [
                moonrun,
                str(WASM_CLI),
                "--",
                "release",
                "prepare",
                str(config_path),
                "--out-dir",
                str(output_dir),
                "-o",
                str(report_path),
                "--moonhostabi",
                moonhostabi,
            ]
            if wasm_opt is not None:
                command.extend(["--wasm-opt", wasm_opt])
            if summary_path is not None:
                command.extend(["--summary", str(summary_path)])
            result = run(command, expected=expected_code)
            if report_path.exists():
                report = json.loads(report_path.read_text(encoding="utf-8"))
                require(report.get("format_version") == 1, f"{name}: wrong report version")
                require(report.get("mode") == "prepare", f"{name}: wrong report mode")
                return report, result
            return None, result

        def write_config(name: str, value: dict[str, Any]) -> Path:
            path = work / f"{name}.json"
            path.write_text(json.dumps(value), encoding="utf-8")
            return path

        def invoke_prepare(
            config_path: Path,
            output_dir: Path,
            report_path: Path,
            expected_code: int,
            *,
            wasm_opt: str | None = None,
            summary_path: Path | None = None,
        ) -> subprocess.CompletedProcess[str]:
            command = [
                moonrun,
                str(WASM_CLI),
                "--",
                "release",
                "prepare",
                str(config_path),
                "--out-dir",
                str(output_dir),
                "-o",
                str(report_path),
                "--moonhostabi",
                moonhostabi,
            ]
            if wasm_opt is not None:
                command.extend(["--wasm-opt", wasm_opt])
            if summary_path is not None:
                command.extend(["--summary", str(summary_path)])
            return run(command, expected=expected_code)

        # The allowlist is unrestricted when omitted, and exact when present.
        report, _ = check(
            "default-allowlist",
            config_for(artifact("imported", "plain.wasm")),
        )
        require(report is not None and report["status"] == "passed", "missing allowlist should pass")
        imported = report["artifacts"][0]
        require(imported["before"]["imports"] == [{"module": "env", "name": "log"}], "import facts mismatch")
        require(imported["findings"] == [], "missing allowlist unexpectedly rejected import")

        report, _ = check(
            "empty-allowlist",
            config_for(artifact("imported", "plain.wasm", {"allowed_imports": []})),
            expected_code=1,
        )
        require(report is not None and report["status"] == "failed", "empty allowlist should fail")
        finding = report["artifacts"][0]["findings"][0]
        require(finding["rule"] == "allowed_imports", "wrong allowlist finding")
        require(finding["actual"] == [{"module": "env", "name": "log"}], "allowlist actual mismatch")
        require(finding["limit"] == [], "empty allowlist limit mismatch")

        report, _ = check(
            "exact-allowlist",
            config_for(
                artifact(
                    "imported",
                    "plain.wasm",
                    {"allowed_imports": [{"module": "env", "name": "log"}]},
                )
            ),
        )
        require(report is not None and report["artifacts"][0]["findings"] == [], "matching allowlist should pass")

        # Limits accept equality, reject one byte over, and aggregate duplicate custom sections.
        report, _ = check(
            "budget-boundary-pass",
            config_for(
                artifact(
                    "decorated",
                    "decorated.wasm",
                    {
                        "max_bytes": len(decorated),
                        "section_budgets": {"custom:meta": custom_total},
                        "required_custom_sections": ["meta"],
                    },
                )
            ),
        )
        require(report is not None and report["status"] == "passed", "budget equality should pass")
        facts = report["artifacts"][0]["after"]
        require(facts["custom_sections"] == ["meta", "meta"], "duplicate custom sections were not reported")
        sections = facts["sections"]
        custom_metrics = [item for item in sections if item["name"] == "custom:meta"]
        require(len(custom_metrics) == 2, "duplicate custom section metrics missing")
        require(sum(item["bytes"] for item in custom_metrics) == custom_total, "custom section byte total mismatch")

        report, _ = check(
            "budget-boundary-fail",
            config_for(
                artifact(
                    "decorated",
                    "decorated.wasm",
                    {
                        "max_bytes": len(decorated) - 1,
                        "section_budgets": {"custom:meta": custom_total - 1},
                        "required_custom_sections": ["absent"],
                        "forbidden_custom_sections": ["meta"],
                    },
                )
            ),
            expected_code=1,
        )
        require(report is not None, "budget failure report missing")
        findings = report["artifacts"][0]["findings"]
        by_rule = {item["rule"]: item for item in findings}
        require(by_rule["max_bytes"]["actual"] == len(decorated), "max_bytes actual mismatch")
        require(by_rule["max_bytes"]["limit"] == len(decorated) - 1, "max_bytes limit mismatch")
        require(by_rule["section_budget:custom:meta"]["actual"] == custom_total, "aggregated budget actual mismatch")
        require(by_rule["section_budget:custom:meta"]["limit"] == custom_total - 1, "section budget limit mismatch")
        require(by_rule["required_custom_section:absent"]["actual"] is False, "required section actual mismatch")
        require(by_rule["forbidden_custom_section:meta"]["actual"] is True, "forbidden section actual mismatch")

        for delta, expected_code, expected_findings in (
            (growth, 0, []),
            (growth - 1, 1, ["max_growth_bytes"]),
        ):
            report, _ = check(
                f"growth-{delta}",
                config_for(
                    artifact(
                        "grown",
                        "decorated.wasm",
                        {"max_growth_bytes": delta},
                        baseline="plain.wasm",
                    )
                ),
                expected_code=expected_code,
            )
            require(report is not None, "growth report missing")
            actual_findings = [item["rule"] for item in report["artifacts"][0]["findings"]]
            require(actual_findings == expected_findings, f"growth findings mismatch: {actual_findings}")
            if expected_findings:
                item = report["artifacts"][0]["findings"][0]
                require(item["actual"] == growth and item["limit"] == growth - 1, "growth actual/limit mismatch")

        absolute_report, _ = check(
            "absolute-paths",
            config_for(
                artifact(
                    "absolute",
                    str((work / "decorated.wasm").resolve()),
                    {"max_growth_bytes": growth},
                    baseline=str((work / "plain.wasm").resolve()),
                )
            ),
        )
        require(absolute_report is not None and absolute_report["status"] == "passed", "absolute artifact/baseline paths should pass")

        # The report writer must refuse to truncate an input path.
        input_before = (work / "plain.wasm").read_bytes()
        collision_report, _ = check(
            "output-over-input",
            config_for(artifact("plain", "plain.wasm")),
            expected_code=2,
            output_path=work / "plain.wasm",
        )
        require(collision_report is None, "report output collision unexpectedly produced JSON")
        require((work / "plain.wasm").read_bytes() == input_before, "report output collision modified the input")

        hardlink_report_path = work / "hardlink-report.json"
        try:
            os.link(work / "plain.wasm", hardlink_report_path)
        except OSError as error:
            print(f"SKIP hardlink report: {error}")
        else:
            linked_report, _ = check(
                "report-hardlink-to-input",
                config_for(artifact("plain", "plain.wasm")),
                output_path=hardlink_report_path,
            )
            require(linked_report is not None and linked_report["status"] == "passed", "hardlink report write failed")
            require((work / "plain.wasm").read_bytes() == input_before, "atomic report write modified the hardlinked input")

        # Prepare strips only the selected names, then evaluates rules on those final bytes.
        kept_section = custom_section("kept", b"retain")
        prepared_input = base + first + second + kept_section
        (work / "prepared-input.wasm").write_bytes(prepared_input)
        prepared_size = len(base + kept_section)
        prepare_rules = {
            "max_bytes": prepared_size,
            "max_growth_bytes": 0,
            "required_custom_sections": ["kept"],
            "forbidden_custom_sections": ["meta"],
        }
        prepare_config = config_for(
            artifact(
                "core",
                "prepared-input.wasm",
                prepare_rules,
                baseline="prepared-input.wasm",
                process={"strip_custom_sections": ["meta"]},
            )
        )
        original_prepared_input = (work / "prepared-input.wasm").read_bytes()
        prepare_dir = work / "prepared-success"
        prepare_report, _ = prepare(
            "prepare-strip-pass",
            prepare_config,
            prepare_dir,
        )
        require(prepare_report is not None and prepare_report["status"] == "passed", "prepare strip should pass final-output rules")
        prepared_artifact = prepare_report["artifacts"][0]
        require(prepared_artifact["before"]["custom_sections"] == ["meta", "meta", "kept"], "prepare before facts mismatch")
        require(prepared_artifact["before"]["sha256"] == hashlib.sha256(prepared_input).hexdigest(), "prepare before hash mismatch")
        require(prepared_artifact["baseline"]["custom_sections"] == ["meta", "meta", "kept"], "prepare must leave baseline unprocessed")
        require(prepared_artifact["baseline"]["sha256"] == hashlib.sha256(prepared_input).hexdigest(), "prepare baseline hash mismatch")
        require(prepared_artifact["after"]["custom_sections"] == ["kept"], "prepare did not strip the exact custom-section name")
        require(prepared_artifact["after"]["bytes"] == prepared_size, "prepare after byte count mismatch")
        prepared_output = prepare_dir / "core.wasm"
        require(prepared_output.is_file(), "prepare did not publish id.wasm")
        require(prepared_output.read_bytes() == base + kept_section, "prepare output bytes do not match exact stripping")
        require(prepared_artifact["after"]["sha256"] == hashlib.sha256(prepared_output.read_bytes()).hexdigest(), "prepare after facts do not describe published bytes")
        require((work / "prepared-input.wasm").read_bytes() == original_prepared_input, "prepare modified its input")

        # The same policy rejects the unprocessed input in check mode.
        check_report, _ = check(
            "same-rules-check-original",
            config_for(
                artifact(
                    "core",
                    "prepared-input.wasm",
                    prepare_rules,
                    baseline="prepared-input.wasm",
                )
            ),
            expected_code=1,
        )
        require(check_report is not None, "check of unprocessed bytes report missing")
        check_rules = {finding["rule"] for finding in check_report["artifacts"][0]["findings"]}
        require("max_bytes" in check_rules and "forbidden_custom_section:meta" in check_rules, "check did not evaluate original bytes")

        over_budget_dir = work / "prepare-over-budget"
        over_budget_config = config_for(
            artifact(
                "core",
                "prepared-input.wasm",
                {"max_bytes": prepared_size - 1},
                process={"strip_custom_sections": ["meta"]},
            )
        )
        over_budget_report, _ = prepare(
            "prepare-over-budget",
            over_budget_config,
            over_budget_dir,
            expected_code=1,
        )
        require(over_budget_report is not None, "over-budget prepare report missing")
        require(over_budget_report["artifacts"][0]["after"]["bytes"] == prepared_size, "over-budget rules were not applied to transformed bytes")
        require(not over_budget_dir.exists(), "failed prepare published its output directory")

        # A failing artifact prevents the whole batch from being published.
        mixed_prepare_dir = work / "prepare-mixed-batch"
        mixed_prepare_config = config_for(
            artifact(
                "good",
                "prepared-input.wasm",
                {"max_bytes": prepared_size},
                process={"strip_custom_sections": ["meta"]},
            ),
            artifact(
                "bad",
                "prepared-input.wasm",
                {"max_bytes": prepared_size - 1},
                process={"strip_custom_sections": ["meta"]},
            ),
        )
        mixed_prepare_report, _ = prepare(
            "prepare-mixed-batch",
            mixed_prepare_config,
            mixed_prepare_dir,
            expected_code=1,
        )
        require(mixed_prepare_report is not None and len(mixed_prepare_report["artifacts"]) == 2, "failed prepare batch report incomplete")
        require(mixed_prepare_report["artifacts"][0]["status"] == "passed", "successful batch artifact status mismatch")
        require(mixed_prepare_report["artifacts"][1]["status"] == "failed", "failing batch artifact status mismatch")
        require(not mixed_prepare_dir.exists(), "partially successful batch published output")

        # Prepare requires a brand-new path, including when the existing directory is empty.
        existing_empty = work / "prepare-existing-empty"
        existing_empty.mkdir()
        existing_empty_config = write_config(
            "prepare-existing-empty",
            config_for(artifact("plain", "plain.wasm")),
        )
        empty_failure = invoke_prepare(
            existing_empty_config,
            existing_empty,
            work / "prepare-existing-empty.report.json",
            expected_code=2,
        )
        require("".join(empty_failure.stdout + empty_failure.stderr), "empty-directory refusal should return diagnostics")
        require(list(existing_empty.iterdir()) == [], "prepare changed the pre-existing empty directory")

        existing_with_file = work / "prepare-existing-sentinel"
        existing_with_file.mkdir()
        sentinel = existing_with_file / "keep.txt"
        sentinel.write_text("preserve me", encoding="utf-8")
        sentinel_config = write_config(
            "prepare-existing-sentinel",
            config_for(artifact("plain", "plain.wasm")),
        )
        invoke_prepare(
            sentinel_config,
            existing_with_file,
            work / "prepare-existing-sentinel.report.json",
            expected_code=2,
        )
        require(sentinel.read_text(encoding="utf-8") == "preserve me", "prepare modified an existing output sentinel")
        require((work / "plain.wasm").read_bytes() == base, "prepare failure modified an input")

        # A report write failure after publication must roll back the new output directory.
        rollback_dir = work / "prepare-report-rollback"
        missing_report_parent = work / "missing-report-parent"
        rollback_config = write_config(
            "prepare-report-rollback",
            config_for(artifact("plain", "plain.wasm")),
        )
        old_summary = work / "previous-summary.md"
        old_summary_bytes = "Previous release: 保留此报告\n".encode("utf-8")
        old_summary.write_bytes(old_summary_bytes)
        invoke_prepare(
            rollback_config,
            rollback_dir,
            missing_report_parent / "report.json",
            expected_code=2,
            summary_path=old_summary,
        )
        require(old_summary.read_bytes() == old_summary_bytes, "failed JSON write did not restore the previous Markdown report")
        require(not rollback_dir.exists(), "failed report write left the published output directory")
        require(not missing_report_parent.exists(), "failed report write created its missing parent")
        require((work / "plain.wasm").read_bytes() == base, "report rollback modified an input")

        # A report path reached through a symlinked ancestor must not enter the new output tree.
        if os.name != "posix":
            print("SKIP symlink report path: this regression requires POSIX symlink semantics")
        else:
            symlink_alias = work / "symlink-alias"
            try:
                symlink_alias.symlink_to(work, target_is_directory=True)
            except (OSError, NotImplementedError) as error:
                print(f"SKIP symlink report path: {error}")
            else:
                symlink_output = work / "prepare-symlink-output"
                symlink_report = symlink_alias / symlink_output.name / "plain.wasm"
                symlink_config = write_config(
                    "prepare-symlink-output",
                    config_for(artifact("plain", "plain.wasm")),
                )
                invoke_prepare(
                    symlink_config,
                    symlink_output,
                    symlink_report,
                    expected_code=2,
                )
                require(not symlink_output.exists(), "symlinked report path allowed output publication")
                require(not symlink_report.exists(), "symlinked report path was created")
                require((work / "plain.wasm").read_bytes() == base, "symlink refusal modified an input")

        # Exercise the installed optimizer when available; then validate its actual output.
        wasm_opt = os.environ.get("WASM_OPT") or shutil.which("moon-wasm-opt")
        if not wasm_opt:
            print("SKIP optimize: set WASM_OPT or add moon-wasm-opt to PATH")
        else:
            (work / "optimize.wat").write_text(
                '(module (func (export "run") (result i32) i32.const 7))\n',
                encoding="utf-8",
            )
            run(
                [
                    moonrun,
                    str(WASM_CLI),
                    "--",
                    "parse",
                    str(work / "optimize.wat"),
                    "-o",
                    str(work / "optimize.wasm"),
                ]
            )
            optimized_dir = work / "prepare-optimized"
            optimized_report, _ = prepare(
                "prepare-optimized",
                config_for(
                    artifact(
                        "optimized",
                        "optimize.wasm",
                        {},
                        process={"optimize": "-Oz"},
                    )
                ),
                optimized_dir,
                wasm_opt=wasm_opt,
            )
            require(optimized_report is not None and optimized_report["status"] == "passed", "real optimizer prepare failed")
            optimized_output = optimized_dir / "optimized.wasm"
            require(optimized_output.is_file(), "optimizer output was not published")
            run([moonrun, str(WASM_CLI), "--", "validate", str(optimized_output)])

        # A malformed artifact does not suppress reports for valid siblings.
        (work / "invalid.wasm").write_bytes(b"not a wasm module")
        report, _ = check(
            "mixed-batch",
            config_for(
                artifact("valid", "plain.wasm"),
                artifact("invalid", "invalid.wasm"),
            ),
            expected_code=1,
        )
        require(report is not None and len(report["artifacts"]) == 2, "mixed batch report omitted an artifact")
        require(report["artifacts"][0]["status"] == "passed", "valid batch member did not pass")
        require(report["artifacts"][0]["after"]["sha256"] == hashlib.sha256(base).hexdigest(), "valid batch hash mismatch")
        require(report["artifacts"][1]["status"] == "failed", "invalid batch member status mismatch")
        require(report["artifacts"][1]["error"], "invalid batch member error missing")

        # Strict JSON schema checks reject unknown and repeated keys before producing a report.
        bad_configs = [
            ("unknown-key", '{"format_version":1,"artifacts":[],"unexpected":true}', "unknown key"),
            (
                "duplicate-key",
                '{"format_version":1,"format_version":1,"artifacts":[]}',
                "duplicate",
            ),
            ("unknown-rule", json.dumps(config_for(artifact("x", "plain.wasm", {"unknown": 1}))), "unknown key"),
        ]
        for name, raw, expected_message in bad_configs:
            report, result = check(name, {}, expected_code=2, raw=raw)
            require(report is None, f"{name}: invalid config unexpectedly produced a report")
            require(expected_message in (result.stdout + result.stderr).lower(), f"{name}: missing schema error")

        if not abi_available:
            print("SKIP ABI: set MOONHOSTABI to a real MoonHostABI executable")
        else:
            require(
                Path(moonhostabi).is_file() or shutil.which(moonhostabi) is not None,
                f"MOONHOSTABI executable not found: {moonhostabi}",
            )
            for filename, source in (
                ("abi-base", '(module (func (export "run") (param i32)))'),
                ("abi-breaking", '(module (func (export "run") (param i32 i32)))'),
            ):
                (work / f"{filename}.wat").write_text(source + "\n", encoding="utf-8")
                run(
                    [
                        moonrun,
                        str(WASM_CLI),
                        "--",
                        "parse",
                        str(work / f"{filename}.wat"),
                        "-o",
                        str(work / f"{filename}.wasm"),
                    ]
                )
            run([moonhostabi, "lock", str(work / "abi-base.wasm"), "--out", str(work / "abi-lock.json")])
            base_report, _ = check(
                "abi-compatible",
                config_for(
                    artifact(
                        "abi",
                        "abi-base.wasm",
                        {},
                        abi={"baseline": "abi-lock.json"},
                    )
                ),
            )
            require(base_report is not None, "compatible ABI report missing")
            compatible = base_report["artifacts"][0]["abi"]
            require(compatible["passed"] is True and compatible["exit_code"] == 0, "compatible ABI result mismatch")
            raw_compatible = compatible["report"]
            require(raw_compatible["outcome"] == "compatible", "raw ABI compatible outcome missing")
            require(
                raw_compatible["artifact"]["sha256"] == base_report["artifacts"][0]["after"]["sha256"],
                "raw ABI artifact hash mismatch",
            )

            abi_prepared_input = work / "abi-prepared-input.wasm"
            abi_prepared_input.write_bytes(
                (work / "abi-base.wasm").read_bytes() + custom_section("abi-meta", b"discard")
            )
            abi_prepare_dir = work / "prepare-abi-final-bytes"
            abi_prepare_report, _ = prepare(
                "prepare-abi-final-bytes",
                config_for(
                    artifact(
                        "abi-final",
                        abi_prepared_input.name,
                        {},
                        process={"strip_custom_sections": ["abi-meta"]},
                        abi={"baseline": "abi-lock.json"},
                    )
                ),
                abi_prepare_dir,
            )
            require(abi_prepare_report is not None, "prepared ABI report missing")
            abi_final_artifact = abi_prepare_report["artifacts"][0]
            require(abi_final_artifact["after"]["sha256"] == hashlib.sha256((work / "abi-base.wasm").read_bytes()).hexdigest(), "prepare ABI after hash is not the stripped output hash")
            prepared_abi = abi_final_artifact["abi"]
            require(prepared_abi["passed"] is True and prepared_abi["exit_code"] == 0, "prepared final-byte ABI check failed")
            require(prepared_abi["report"]["outcome"] == "compatible", "prepared final-byte raw ABI outcome mismatch")
            require(prepared_abi["report"]["artifact"]["sha256"] == abi_final_artifact["after"]["sha256"], "ABI did not verify the final prepared bytes")

            breaking_report, _ = check(
                "abi-breaking",
                config_for(
                    artifact(
                        "abi",
                        "abi-breaking.wasm",
                        {},
                        abi={"baseline": "abi-lock.json"},
                    )
                ),
                expected_code=1,
            )
            require(breaking_report is not None, "breaking ABI report missing")
            breaking = breaking_report["artifacts"][0]["abi"]
            require(breaking["passed"] is False and breaking["exit_code"] == 2, "breaking ABI result mismatch")
            raw_breaking = breaking["report"]
            require(raw_breaking["outcome"] == "breaking", "raw ABI breaking outcome mismatch")
            require(
                raw_breaking["artifact"]["sha256"] == breaking_report["artifacts"][0]["after"]["sha256"],
                "breaking ABI artifact hash mismatch",
            )

        print("release check and prepare integration checks passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, json.JSONDecodeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
