#!/bin/sh
# Windows-side smoke test, run from WSL via interop.
#
#   WIN_MOONRUN='C:/Users/me/.moon/bin/moonrun.exe' \
#   WIN_WASM_OPT='C:/Users/me/.moon/bin/moon-wasm-opt.exe' \
#   WIN_TMP='C:/Temp' WSL_TMP='/mnt/c/Temp' ./tests/win-smoke.sh
#
# The wasm asset is the same one moonx downloads; this checks that the wasm
# target and its async runtime work under Windows paths and Windows moonrun.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${WIN_MOONRUN:?set WIN_MOONRUN to moonrun.exe}"
: "${WIN_WASM_OPT:?set WIN_WASM_OPT to moon-wasm-opt.exe}"
WIN_TMP=${WIN_TMP:-C:/Temp}
WSL_TMP=${WSL_TMP:-/mnt/c/Temp}

wasm=$(wslpath -w "$root/_build/wasm/debug/build/wasm-tools.wasm")
mkdir -p "$WSL_TMP"

run() {
  "$WIN_MOONRUN" "$wasm" -- "$@"
}

expect() {
  name=$1 expected_code=$2 expected_text=$3
  shift 3
  set +e
  actual_text=$(run "$@" 2>&1)
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

expect version 0 'wsm 0.4.1' --version
expect help 0 'Usage: wsm <COMMAND>' --help

hello_win="$WIN_TMP/wsm-hello.wasm"
hello_wsl="$WSL_TMP/wsm-hello.wasm"
expect parse 0 '' parse "$(wslpath -w "$root/tests/fixtures/hello.wat")" -o "$hello_win"
expect validate 0 'valid core module' validate "$hello_win"
expect dump 0 'code' dump "$hello_win"
expect size 0 'call graph' size "$hello_win"
expect budget-fail 1 'exceeds budget' size --budget 10B "$hello_win"
expect diff 0 'no function size changes' size --diff "$hello_win" "$hello_win"

expect symbolize 0 'name add' symbolize "$hello_win" 'wasm-function[0]:0x2d'

compose_win="$WIN_TMP/wsm-composed.wasm"
expect compose 0 '' compose "$(wslpath -w "$root/tests/fixtures/wac/main.wac")" -o "$compose_win"
expect compose-validate 0 'valid component' validate "$compose_win"

opt_win="$WIN_TMP/wsm-hello.opt.wasm"
expect opt 0 '' opt --wasm-opt "$WIN_WASM_OPT" -Oz "$hello_win" -o "$opt_win"
expect opt-validate 0 'valid core module' validate "$opt_win"

echo "all windows cli checks passed"
