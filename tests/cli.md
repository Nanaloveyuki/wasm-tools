# wsm CLI

Run from `tests/` after `moon build --target wasm`. Each `$` line is one command;
`[N]` is the exit code and defaults to `0`.

## Version and help

```console
$ ../run.sh --version
wsm 0.1.0

$ ../run.sh --help
wsm - WebAssembly binary toolkit
...
```

## Core module round trip

```console
$ ../run.sh parse fixtures/hello.wat -o hello.wasm

$ ../run.sh validate hello.wasm
valid core module (74 bytes)

$ ../run.sh contract snapshot hello.wasm -o hello.abi.json

$ ../run.sh contract check --baseline hello.abi.json hello.wasm --direction both
provided: compatible
  no interface changes
required: compatible
  no interface changes

$ ../run.sh print hello.wasm
(module
  (type (;0;) (func (param i32) (param i32) (result i32)))
  ...
```

## Component round trip

```console
$ ../run.sh parse fixtures/component.wat -o component.wasm

$ ../run.sh validate component.wasm
valid component (102 bytes)

$ ../run.sh print component.wasm
; ---- root ----
(component
  ...
```

## Errors

```console
$ ../run.sh validate fixtures/not-wasm.wasm
wsm: missing wasm magic header
[1]

$ ../run.sh validate fixtures/truncated.wasm
wsm: parse: length out of bounds
[1]

$ ../run.sh validate missing.wasm
wsm: no such file: missing.wasm
[2]

$ ../run.sh validate --nope fixtures/not-wasm.wasm
wsm: unknown option: --nope
Run `wsm --help` for usage.
[2]
```

## Pipes and dump

```console
$ cat fixtures/hello.wat | ../run.sh parse - | ../run.sh validate -
valid core module (74 bytes)

$ ../run.sh dump fixtures/truncated.wasm
wsm: section 1 at 8 claims 127 bytes, past end of input
[1]
```

## Strip

```console
$ ../run.sh strip hello.wasm | ../run.sh metadata -
custom sections: 0
module name: (none)
function names: 0
producers: (none)
```
