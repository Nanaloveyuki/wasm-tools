#!/bin/sh
# Reproducible end-to-end contract demo using real MoonBit wasm/wasm-gc outputs.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
wsm="$root/run.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

moon build --target wasm >/dev/null
moon build examples --target wasm >/dev/null
moon build examples --target wasm-gc >/dev/null
moon build examples/contract-breaking --target wasm >/dev/null
moon build examples/contract-breaking --target wasm-gc >/dev/null

wasm_v1="$root/_build/wasm/debug/build/examples/examples.wasm"
gc_v1="$root/_build/wasm-gc/debug/build/examples/examples.wasm"
wasm_v2="$root/_build/wasm/debug/build/examples/contract-breaking/contract-breaking.wasm"
gc_v2="$root/_build/wasm-gc/debug/build/examples/contract-breaking/contract-breaking.wasm"

"$wsm" contract snapshot "$wasm_v1" -o "$tmp/wasm-v1.json"
"$wsm" contract snapshot "$gc_v1" -o "$tmp/wasm-gc-v1.json"
"$wsm" contract snapshot "$wasm_v2" -o "$tmp/wasm-v2.json"
"$wsm" contract snapshot "$gc_v2" -o "$tmp/wasm-gc-v2.json"

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
  printf '%s\n' "$actual_text"
}

expect_contains() {
  name=$1 expected_text=$2
  shift 2
  actual_text=$("$@" 2>&1)
  case "$actual_text" in
    *"$expected_text"*) echo "ok   $name" ;;
    *)
      echo "FAIL $name: output did not contain $expected_text" >&2
      printf '%s\n' "$actual_text" >&2
      exit 1
      ;;
  esac
}

expect_contains wasm-v1-signature '"params":["i32","i32"]' cat "$tmp/wasm-v1.json"
expect_contains wasm-gc-v1-signature '"params":["i32","i32"]' cat "$tmp/wasm-gc-v1.json"
expect_contains wasm-v2-signature '"params":["i32","i32","i32"]' cat "$tmp/wasm-v2.json"
expect_contains wasm-gc-v2-signature '"params":["i32","i32","i32"]' cat "$tmp/wasm-gc-v2.json"

echo '== Same MoonBit ABI across wasm and wasm-gc =='
expect cross-target-compatible 0 'required: compatible' \
  "$wsm" contract check --baseline "$tmp/wasm-v1.json" "$gc_v1" --direction both

echo '== Adding a required parameter is breaking for existing callers =='
expect wasm-signature-breaking 1 'export add (function): export type changed' \
  "$wsm" contract check --baseline "$tmp/wasm-v1.json" "$wasm_v2" --direction provided
expect wasm-gc-signature-breaking 1 'export add (function): export type changed' \
  "$wsm" contract check --baseline "$tmp/wasm-gc-v1.json" "$gc_v2" --direction provided

echo 'MoonBit contract demo passed.'
