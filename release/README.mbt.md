# release

`release` defines the version 1 release policy configuration and evaluates
policy rules over artifact facts supplied by the caller. It has no filesystem,
WASM parser, CLI, or MoonHostABI dependency; those adapters belong to the
command layer.

## Configuration

```json
{
  "format_version": 1,
  "artifacts": [
    {
      "id": "app",
      "input": "dist/app.wasm",
      "baseline": "release/app.wasm",
      "abi": { "baseline": "release/app.hostabi.json" },
      "rules": {
        "max_bytes": 200000,
        "max_growth_bytes": 8192,
        "max_growth_percent": 10,
        "section_budgets": { "code": 120000, "custom:producers": 256 },
        "allowed_imports": [{ "module": "env", "name": "log" }],
        "required_custom_sections": ["producers"],
        "forbidden_custom_sections": ["debug_info"]
      }
    }
  ]
}
```

`format_version` must be `1`, and `artifacts` must contain at least one
artifact. Each artifact requires `id`, `input`, and `rules`. `baseline`, `abi`,
and `process` are optional. Omitted or `null` optional scalar fields mean
“not configured”; `process` defaults to no transformation, and omitted rule
collections default to empty. Unknown keys, duplicate JSON keys, duplicate
artifact IDs (case-insensitive), invalid types, out-of-range values, and
contradictory required/forbidden/strip section rules are rejected.

Artifact IDs use only ASCII letters, digits, `_`, and `-`; Windows device names
are reserved. IDs identify output artifacts and do not configure output paths.
Import allowlists match exact `{module, name}` pairs; an empty array denies all
imports, while omitted or `null` means no allowlist. Empty import names and
custom section names are valid exact values.

`baseline` refers to the previous final WASM artifact used for size growth
checks. `abi.baseline` refers to the MoonHostABI lock used by the external ABI
verifier. These are different files and have different formats.

Section budgets use core section labels: `type`, `import`, `function`, `table`,
`memory`, `global`, `export`, `start`, `element`, `code`, `data`, `data-count`,
and `tag`. Custom section budgets use `custom:<exact-name>`; `custom:` matches
an empty custom section name. Repeated sections with the same label are summed
before the limit is checked.

## Evaluation

`evaluate` checks absolute bytes, growth bytes and percentage, aggregate section
budgets, exact import allowlists, and required/forbidden custom sections. A
configured growth rule without baseline facts yields a finding. Shrinking
artifacts satisfy growth limits. For a zero-byte baseline, any positive growth
exceeds every percentage limit; no growth passes. Percentage comparison uses
integer cross multiplication, so it does not round at the configured boundary.

Findings are returned in rule order, with section budget findings sorted by
label. The caller is responsible for converting each finding into the release
report and for running ABI verification and post-processing checks.
