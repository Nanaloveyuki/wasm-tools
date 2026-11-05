# wasm-tools

MoonBit 的 WebAssembly 二进制工具箱。把 `wasm_core`、`wasm_component`、
`moonrockz/wit` 的能力组合成一个统一 CLI，可通过 `moonx` 直接运行，也可
`moon install` 安装为本地命令。命令别名为 `wsm`。

## 安装与运行

```sh
# 已发布版本，无需安装
moonx Nanaloveyuki/wasm-tools validate app.wasm

# 或安装到 ~/.moon/bin/wasm-tools（wsm 是使用名/别名）
moon install Nanaloveyuki/wasm-tools
alias wsm=wasm-tools
wsm validate app.wasm
```

## 命令

| 命令 | 作用 |
|---|---|
| `validate [FILE]` | 自动识别 core module / component，解析并验证 |
| `print [FILE]` | 二进制转 WAT；component 按文档分段输出 |
| `parse [FILE]` | WAT / component WAT 转二进制 |
| `dump [FILE]` | section 表；`--instructions` 追加逐指令 offset，`--json` 输出结构化结果 |
| `strip [FILE]` | 删除 custom section；`--keep NAME` 保留指定段 |
| `metadata [FILE]` | 展示 `name` 与 `producers` custom section |
| `size [FILE]` | section、函数体大小与调用图；`--top N`、`--json` |
| `component wit [FILE]` | 从 component 提取内嵌 WIT 包 |

通用约定：

- 输入缺省为 stdin，`-` 也表示 stdin；`-o FILE` 指定输出文件。
- 二进制输出默认写 stdout，重定向由调用方负责（当前没有可移植的 isatty）。
- 退出码：`0` 成功，`1` 内容非法或不支持，`2` 用法或 IO 错误。

```sh
wsm parse app.wat -o app.wasm
wsm validate app.wasm
wsm print app.wasm -o app.wat
wsm dump --instructions app.wasm | head
wsm strip app.wasm --keep producers -o app.stripped.wasm
wsm metadata --json app.wasm
cat app.wasm | wsm validate -
```

## 范围

本工具只做二进制层：

- core module 走 `Milky2018/wasm_core`（解析、验证、WAT 双向、编码）
- component 走 `Milky2018/wasm_component`（解析、验证、WIT）
- component → WAT 走 `moonrockz/wit/decompiler`
- WIT/WAC 的 parse/format/verify 交给 `moonx moonrockz/wasm-devkit`
- 优化交给工具链自带的 `moon-wasm-opt`

不做：运行时/JIT、优化 pass、WIT/WAC 语言工具、`smith`/`mutate`/`shrink`、
`component new`/`embed`。设计理由见 [docs/adr](docs/adr/README.md)。

`dump`/`metadata` 对 component 使用独立的 section id 表；`size` 对 component
只报告 section 明细，函数与调用图仅对 core module 有效。

## 路线

| 版本 | 内容 |
|---|---|
| 0.1.0 | validate / print / parse / dump / strip / metadata / component wit |
| 0.2.0（当前） | component 感知的 dump/metadata；`size` v1（section、函数、调用图） |
| 0.3.0 | `opt`（包装 `moon-wasm-opt`）；`size --diff`/`--budget` |
| 0.4.0 | `compose`（WAC）；`addr2line`（依赖 spike 通过） |

详细设计与验收见 [0004-post-0.1-roadmap](docs/adr/0004-post-0.1-roadmap.md)。

## 开发

```sh
moon build --target wasm       # 生成 _build/wasm/debug/build/wasm-tools.wasm
moon build --target native     # 本地可执行文件
moon test                      # 单元测试（raw 层）
./tests/smoke.sh               # CLI 行为检查，读取 tests/cli.md 的场景
```

`./run.sh` 用本地 wasm 构建运行 CLI，`tests/smoke.sh` 依赖它。

## 结构

```text
main.mbt          argv 转发与退出码
cli/              参数、IO、帮助、错误（不依赖 wasm 包）
cmd/              每个子命令一个文件
wasm/             唯一的适配层：raw 扫描、core、component、dump
tests/            fixtures、cli.md 场景、smoke.sh
docs/adr/         范围、依赖与发布决策
```

依赖方向为 `main → cmd → wasm → 上游包`。`cli` 可被 `cmd` 依赖但不得依赖
`wasm`；`wasm` 不得依赖 `cmd`。
