#!/bin/sh
# Executable form of tests/cli.md. Fails on the first mismatch.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root/tests"
wsm="$root/run.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

expect() {
  name=$1 expected_code=$2 expected_text=$3
  shift 3
  set +e
  actual_text=$("$@" 2>&1)
  actual_code=$?
  set -e
  if [ "$actual_code" -ne "$expected_code" ]; then
    echo "FAIL $name: exit $actual_code, want $expected_code" >&2
    printf '%s\n' "$actual_text" >&2
    exit 1
  fi
  case "$actual_text" in
    *"$expected_text"*) ;;
    *)
      echo "FAIL $name: output did not contain $expected_text" >&2
      printf '%s\n' "$actual_text" >&2
      exit 1
      ;;
  esac
  echo "ok   $name"
}

expect version 0 'wsm 0.4.2' "$wsm" --version
expect help 0 'Usage: wsm <COMMAND>' "$wsm" --help

"$wsm" parse fixtures/hello.wat -o "$tmp/hello.wasm"
expect validate-core 0 'valid core module (74 bytes)' "$wsm" validate "$tmp/hello.wasm"
expect print-core 0 '(module' "$wsm" print "$tmp/hello.wasm"
expect dump-core 0 'code' "$wsm" dump "$tmp/hello.wasm"
expect size-core 0 'call graph' "$wsm" size "$tmp/hello.wasm"
expect size-json 0 '"functions"' "$wsm" size --json "$tmp/hello.wasm"
expect size-budget-pass 0 'total 74 B' "$wsm" size --budget 1KB "$tmp/hello.wasm"
expect size-budget-fail 1 'exceeds budget' "$wsm" size --budget 10B "$tmp/hello.wasm"
expect size-diff 0 'no function size changes' "$wsm" size --diff "$tmp/hello.wasm" "$tmp/hello.wasm"
expect opt 0 'valid core module' sh -c "'$wsm' opt '$tmp/hello.wasm' -o '$tmp/hello.opt.wasm' && '$wsm' validate '$tmp/hello.opt.wasm'"
expect symbolize 0 'name add' "$wsm" symbolize "$tmp/hello.wasm" 'wasm-function[0]:0x2d'

expect metadata-core 0 'custom sections: 1' "$wsm" metadata "$tmp/hello.wasm"

"$wsm" parse fixtures/component.wat -o "$tmp/component.wasm"
expect validate-component 0 'valid component (102 bytes)' "$wsm" validate "$tmp/component.wasm"
expect print-component 0 '; ---- root ----' "$wsm" print "$tmp/component.wasm"
expect dump-component 0 'core-module' "$wsm" dump "$tmp/component.wasm"
expect metadata-component 0 'component name' "$wsm" metadata "$tmp/component.wasm"
expect size-component 0 'core-module' "$wsm" size "$tmp/component.wasm"

expect bad-magic 1 'missing wasm magic header' "$wsm" validate fixtures/not-wasm.wasm
expect truncated 1 'length out of bounds' "$wsm" validate fixtures/truncated.wasm
expect missing-file 2 'no such file' "$wsm" validate missing.wasm
expect unknown-option 2 'unknown option: --nope' "$wsm" validate --nope fixtures/hello.wat

"$wsm" strip "$tmp/hello.wasm" -o "$tmp/stripped.wasm"
expect strip-result 0 'custom sections: 0' "$wsm" metadata "$tmp/stripped.wasm"
expect strip-valid 0 'valid core module' "$wsm" validate "$tmp/stripped.wasm"

"$wsm" parse fixtures/component-comment.wat -o "$tmp/component-comment.wasm"
expect component-comment 0 'valid component' "$wsm" validate "$tmp/component-comment.wasm"

cat fixtures/hello.wat | "$wsm" parse - > "$tmp/piped.wasm"
expect pipe-input 0 'valid core module' sh -c "'$wsm' validate - < '$tmp/piped.wasm'"

echo "all cli checks passed"
