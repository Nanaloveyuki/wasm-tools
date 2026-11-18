# bundle

`parse_manifest(text) -> Manifest raise ManifestError` parses and validates a
version 1 publication manifest. `ManifestError.message()` supplies a diagnostic.
The package is pure MoonBit: it performs no filesystem access, WASM parsing,
decompression or consumer execution. The CLI supplies those adapters.

```json
{
  "format_version": 1,
  "root": "dist",
  "files": [
    { "path": "loader.mjs" },
    { "path": "app.wasm", "kind": "wasm" },
    { "path": "app.wasm.gz", "encoding": "gzip", "source": "app.wasm" }
  ],
  "consumers": [{
    "name": "smoke",
    "entry": "loader.mjs",
    "requires": ["app.wasm"],
    "export": "check",
    "args": [],
    "expected": true
  }]
}
```

The parser rejects unknown or duplicate keys, invalid scalar types, nonportable
relative file paths, case-insensitive duplicate paths, file/directory prefix
conflicts, undeclared references and compressed source chains. Files are capped
at 256 entries; consumers at 16. Consumer entries are declared identity `.mjs`
files; names are unique ignoring ASCII case. The root defaults to `.` and is
resolved by the caller relative to the manifest location.

`requires` records explicit references, not an inferred JavaScript dependency
graph. The CLI copies all declared captured files into each consumer's fresh
directory. The caller must still check file existence and types; successful
parsing alone does not establish that a release works.

See the root [README](../README.md) for runtime limits, reports and Action usage,
and [ADR 0013](../docs/adr/0013-release-bundle.md) for the division of responsibilities.
