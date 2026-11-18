#!/usr/bin/env python3
"""Integration checks for `wsm bundle check`."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


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


def manifest_for(*files: dict[str, str]) -> dict[str, object]:
    return {"format_version": 1, "files": list(files)}


def main() -> int:
    moonrun = shutil.which("moonrun")
    require(moonrun is not None, "moonrun is required to run the built wasm CLI")
    require(WASM_CLI.is_file(), f"built wasm CLI not found: {WASM_CLI}")

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

        def write_bundle_manifest(name: str, *files: dict[str, str]) -> Path:
            value = manifest_for(*files)
            value["root"] = "bundle"
            return write_manifest(name, value)

        def invoke(
            manifest: Path,
            *,
            expected: int = 0,
            report_path: Path | None = None,
            summary_path: Path | None = None,
        ) -> tuple[subprocess.CompletedProcess[str], dict[str, object] | None]:
            report_path = report_path or work / f"{manifest.stem}.report.json"
            command = [moonrun, str(WASM_CLI), "--", "bundle", "check", str(manifest), "-o", str(report_path)]
            if summary_path is not None:
                command.extend(["--summary", str(summary_path)])
            result = run(command, expected=expected)
            if expected == 2:
                return result, None
            if not report_path.exists():
                return result, None
            report = json.loads(report_path.read_text(encoding="utf-8"))
            require(report.get("format_version") == 1, "wrong bundle report version")
            require(report.get("mode") == "bundle-check", "wrong bundle report mode")
            return result, report

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
            "bad-root": {"format_version": 1, "root": "../outside", "files": []},
            "missing-root": {"format_version": 1, "root": "missing", "files": []},
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
