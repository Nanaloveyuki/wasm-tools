# 0001 CLI 定位、首版命令面与非目标

- Status: Accepted
- Date: 2026-11-04
- Supersedes: —

## Context

MoonBit 的 wasm 积木已经相当完整：`wasm_core` 提供 core 规范模型、WAT 解析/打印、
二进制编解码与验证；`wasm_component` 提供组件模型解析与验证；`moonrockz/wit`
提供 WIT 与组件反编译；`mizchi/mwac` 提供 WAC 组合；工具链自带
`moon-wasm-opt`（binaryen 125）。缺的是一个统一的二进制入口，以及 `dump`、
`strip`、`metadata`、`size` 这些“开发者体验最后一公里”。

同时 `moonx` 只执行 MoonCakes 上已构建好的 wasm 资产，native-only 的包无法作为
依赖链的一部分。因此这个 CLI 必须自身可编译到 wasm，并且依赖都必须是 wasm
可用的。

## Decision

### 名称与入口

- 发布模块：`<namespace>/wasm-tools`。
- 命令别名：`wsm`（usage/help 中统一使用该名字）。
- 模块根包为 executable，保证 `moonx <namespace>/wasm-tools` 直接运行，不需要
  额外的包路径。
- `supported_targets = "native+wasm"`，`preferred_target = "wasm"`；native
  构建用于本地安装与调试。

### 定位

只做 **wasm 二进制工具**：

- 解析、验证、打印、编码 core module 与 component
- 检查二进制结构（section、offset、function body）
- 修改二进制（去 custom section、后续的元数据写入）
- 体积分析（section/function/call graph/retained）
- 调用外部优化器，不实现优化 pass

### 首版命令面（MVP）

| 命令 | 行为 | 输出 |
|---|---|---|
| `validate [FILE]` | 自动识别 core/component，解析并验证 | 成功静默；失败诊断到 stderr，退出码 1 |
| `print [FILE]` | 二进制转 WAT；core 单文档，component 多文档 | stdout 或 `-o FILE` |
| `parse [FILE]` | WAT/component WAT 转二进制 | stdout 或 `-o FILE` |
| `dump [FILE]` | section 表；`--instructions` 追加指令 offset | 文本或 `--json` |
| `strip [FILE]` | 删除 custom section；默认全部，支持 `--keep NAME` | 二进制到 stdout/`-o` |
| `metadata [FILE]` | 展示 name section 与 producers section | 文本或 `--json` |
| `component wit [FILE]` | 从 component 提取 WIT | stdout 或 `-o FILE` |

通用约定：

- 输入缺省为 stdin，`-` 显式表示 stdin；输入格式按魔数或首个顶层 token 自动识别。
- 二进制输出默认写 stdout；`-o` 写文件。不提供 tty 检测（当前没有可移植的 isatty API），
  由用户显式重定向。
- 退出码：`0` 成功，`1` wasm/WIT 内容非法，`2` 用法或 IO 错误。
- `--json` 只用于结构化报告命令（`dump`、`metadata`、后续 `size`），字段名一旦
  发布即视为稳定接口。

### 已实现范围与限制

- `dump`、`metadata` 只接受 core module；component 的 section id 空间不同，
  在实现组件感知扫描前显式报 `Unsupported`（退出码 1），而不是输出错误的段名。
- `strip` 对 core 和 component 都有效：它只按顶层 section 边界裁剪，不解释内容。
- `parse` 用首个非注释 token 判断 `component`/`module`，不依赖文件扩展名。
- 没有可移植 `isatty`，因此二进制输出不做 tty 保护，由调用方重定向。

### 非目标

- `spawn`/`mutate`/`shrink`/`smith` 等测试生成类命令
- 完整的 `wasm-tools` 兼容层
- `component new`/`embed`：现有库没有 core module 到 component 的完整包装器，
  等真实需求出现再做
- WIT/WAC 的 parse/verify/format：交给 `moonx moonrockz/wasm-devkit`
- 优化 pass：交给 `moon-wasm-opt`
- 运行时、JIT、解释器

## Consequences

- 首版代码量集中在 CLI 与 raw binary 层，不重复实现解析器。
- `print` 的 core/component 两条路径使用不同库，必须在适配层完成格式与错误统一。
- 命令面按子命令分文件，后续可把 `size`/`compose` 作为独立包加入而不改入口。

## Verification

- 对 MoonBit `wasm` 与 `wasm-gc` 的 debug/release 产物执行 `validate` 与
  `print`，两者都必须成功。
- `parse(print(bin))` 重新验证通过；与原始二进制语义等价。
- 非法输入（截断、错误 version、越界 section）退出码为 1，且不 panic。
- 发布后在干净环境执行 `moonx <namespace>/wasm-tools validate fixture.wasm`，
  确认预编译资产可用。

## Reconsideration

如果 `moonrockz/wit` 修复 core 解析器的 256 层嵌套上限，可以重新评估是否用它
统一 core/component 两条路径；在那之前不合并。
