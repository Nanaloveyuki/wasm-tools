#!/usr/bin/env bash
set -euo pipefail

if [[ "${RUNNER_OS:-}" != "Linux" ]]; then
  printf 'This action supports Linux runners only; got %s.\n' "${RUNNER_OS:-unknown}" >&2
  exit 1
fi

case "${INPUT_MODE:-check}" in
  check|prepare) ;;
  *) printf 'mode must be check or prepare; got %s.\n' "$INPUT_MODE" >&2; exit 2 ;;
esac

case "${INPUT_INSTALL_MOONHOSTABI:-false}" in
  true|false) ;;
  *) printf 'install-moonhostabi must be true or false.\n' >&2; exit 2 ;;
esac

action_root="${GITHUB_ACTION_PATH:?GITHUB_ACTION_PATH is required}"
runner_temp="${RUNNER_TEMP:-/tmp}"
toolchain_file="$action_root/.moonbit-toolchain"
if [[ ! -f "$toolchain_file" ]]; then
  printf 'Missing MoonBit toolchain pin: %s\n' "$toolchain_file" >&2
  exit 1
fi
toolchain_version="$(tr -d '\r\n' < "$toolchain_file")"
if [[ -z "$toolchain_version" ]]; then
  printf 'MoonBit toolchain pin is empty.\n' >&2
  exit 1
fi

moon_bin="$HOME/.moon/bin"
export PATH="$moon_bin:$PATH"
if ! command -v moon >/dev/null 2>&1 || ! command -v moonc >/dev/null 2>&1 ||
  ! moonc -v 2>&1 | grep -Fq "$toolchain_version"; then
  installer="$(mktemp "$runner_temp/moonbit-install.XXXXXX.sh")"
  trap 'rm -f "$installer"' EXIT
  curl --retry 3 -fsSL https://cli.moonbitlang.com/install/unix.sh -o "$installer"
  bash "$installer" "$toolchain_version"
  export PATH="$moon_bin:$PATH"
fi

if ! moonc -v 2>&1 | grep -Fq "$toolchain_version"; then
  printf 'MoonBit compiler does not match %s after installation.\n' "$toolchain_version" >&2
  moonc -v >&2 || true
  exit 1
fi

if [[ -n "${GITHUB_PATH:-}" ]]; then
  printf '%s\n' "$moon_bin" >> "$GITHUB_PATH"
fi

target_dir="$(mktemp -d "$runner_temp/wasm-tools-action-build.XXXXXX")"
moon -C "$action_root" build --target wasm --release --target-dir "$target_dir"
cli_wasm="$target_dir/wasm/release/build/wasm-tools.wasm"
if [[ ! -f "$cli_wasm" ]]; then
  printf 'Release CLI build did not produce %s\n' "$cli_wasm" >&2
  exit 1
fi

if [[ "${INPUT_INSTALL_MOONHOSTABI:-false}" == true ]]; then
  abi_bin="$runner_temp/wasm-tools-action-moonhostabi"
  mkdir -p "$abi_bin"
  moon -C "$action_root" install --bin "$abi_bin" 0717lee/moonhostabi/cmd/moonhostabi@0.6.0
  abi_executable="$abi_bin/moonhostabi"
  if [[ ! -x "$abi_executable" ]]; then
    printf 'Pinned MoonHostABI installation did not produce %s\n' "$abi_executable" >&2
    exit 1
  fi
  export PATH="$abi_bin:$PATH"
  printf '%s\n' "$abi_bin" >> "${GITHUB_PATH:?GITHUB_PATH is required}"
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'WSM_CLI_WASM=%s\n' "$cli_wasm" >> "$GITHUB_ENV"
fi
