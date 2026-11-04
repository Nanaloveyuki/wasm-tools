#!/bin/sh
# Run the CLI under the local wasm build; used by tests/cli.md.
set -e
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec moonrun "$root/_build/wasm/debug/build/wasm-tools.wasm" -- "$@"
