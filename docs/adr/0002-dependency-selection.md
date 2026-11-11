# 0002 依赖选择、实测边界与上游协作

- Status: Accepted
- Date: 2026-11-04
- Supersedes: —

## Context

社区已有多份 wasm 相关 MoonBit 包，能力重叠但完整度、目标平台和成熟度差异很大。
选错依赖会导致：wasm 目标编不过、功能缺口自己补、与上游重复维护。

初始结论在 2026-11-04 用 `moon` 0.1.20261029 实际构建验证过，不是从 README 推断的。依赖升级验证记录见文末。

## Decision

### 采用

| 包 | 版本 | 用途 | 关键理由 |
|---|---|---|---|
| `Milky2018/wasm_core` | 0.19.0 | core 二进制解析/编码/验证/WAT 双向 | 指令枚举约 500 个变体，覆盖 GC/SIMD/atomics；解析器可给出逐指令 `byte_offset` |
| `Milky2018/wasm_component` | 0.19.0 | component 解析/验证、WIT 解析/编码/解码 | 提供 `decode_wit_package_from_component` 与 `format_package`，正是 `component wit` 需要的 |
| `moonrockz/wit` | 0.4.0 | **仅** `decompiler`：二进制转 WAT（core + component） | 反编译输出带 offset 的多文档 WAT；index 中 `wasm-devkit` 依赖它 |
| ~~`mizchi/mwac`~~ | 0.2.2 | 暂不采用 | 本地可编到 wasm 并完成组合，但其依赖 `mizchi/wit` 在 Mooncakes 构建服务的工具链上编译失败（`Array::to_json` 不存在）；发布后无预编译资产，因此回退 |
| `moonbitlang/async` | 0.22.9 | 文件、stdio、进程 | `fs`/`stdio`/`process` 支持 wasm；`opt` 用 `process` 调用 `moon-wasm-opt` |

依赖版本全部固定，升级必须重新跑 ADR 末尾的验证清单。

### 运行时外部工具

- `moon-wasm-opt`：MoonBit 工具链自带（本机 125），随 `~/.moon/bin` 分发。
- 我们只负责“发现 + 传参 + 报告退出码”，不 vendor binaryen，不解析其输出。
- 找不到时给出明确提示，而不是静默跳过优化。

### 适配层边界

`wasm_core`、`wasm_component`、`moonrockz/wit` 的错误类型、容器类型、
WAT 文档模型互不兼容。CLI 包内必须有一层薄适配：

- 统一为 `WasmError { Parse, Validate, Io, Unsupported, Usage }`，携带 1-based 行列
  或字节 offset；上游诊断只做格式化，不丢原始消息。
- 统一字节容器为 `Bytes`，入口处完成一次拷贝，内部不反复做 `Array[Byte]`
  与 `Array[Int]` 转换。
- WAT 多文档（`WatDocuments`）在 `print` 时按 `; ---- <title> ----` 分隔输出。

### 不采用（带实测原因）

| 包 | 结论 |
|---|---|
| `jtenner/starshine` | 状态机验证、pass、测试生成很全，但 `src/fs` 在当前工具链编译失败（`ArrayView[String]` vs `Array[String]`），且 `passes` 在 wasm 目标有大量类型错误；只把 `binary`/`validate` 作为差分对照（`wat` 依赖的 `wast` 也编不过），不作为依赖 |
| `mizchi/wite` | 组件构建/优化/分析工具，不是二进制工具箱；0.11.3 的 `moon add` 因 `mizchi/oci_wasm@0.5.0` 仍是旧 manifest 而失败 |
| `mizchi/wasmx` | wasm 运行时，不是工具链 |
| `BigSaltyMan/moonsize` | 声明 `supported_targets = "+native"`，`moonx` 报无预编译资产；体积报告思路可借鉴，但不能作为依赖 |
| `clbbbb/moonbit-wasm-inspect` | 仅“结构 + features + call graph”子集；实测对合法 MoonBit 产物报 `standard sections must be strictly ordered and unique`，说明 section 处理有 bug |
| `zhangbowen2006/wasmslim` | 以 CI 体积门禁为主，`print/parse` 子集与主库重复；实测无预编译资产，`moonx` 不可用 |
| `AdUhTkJm/wasmtools` | 0.1.0 玩具级，能力远小于 `wasm_core` |
| `wuhaiting321/dwarfscope` | 子包可编到 wasm、与 `x@0.5.x` 不冲突，但 MoonBit 的 wasm 产物不生成 DWARF，`addr2line` 没有数据源；不引入 |
| `moonbit-community/cmd` | 组织约定可参考（命令拆包、ADR 风格），但不是 wasm 专用 |

### 上游问题（需要提交，不阻塞首版）

1. `moonrockz/wit` core 解析器把嵌套上限写死为 256，会拒绝深层嵌套的合法模块；
   若采用它作为 core 路径需先修复。
2. `jtenner/starshine` 的 `fs` 与 `passes` 在 wasm 目标编译失败；修复后可重新评估
   用它的 pass 替代 `moon-wasm-opt`（会免掉外部进程依赖）。

## Consequences

- 首版依赖树较小：core/component 来自同一作者，语义一致，减少模型转换。
- 组件 WAT 打印只能走 `moonrockz/wit`，因此组件相关功能必须与其版本绑定。
- 优化必须依赖宿主进程能力；纯沙箱环境（禁止 spawn）下 `opt` 不可用，需在
  `doctor` 类输出中说明。

## Verification

每次升级任一依赖后重跑：

```sh
moon build --target wasm
moon build --target native
moon test
```

并用下列固件跑一遍 `validate` / `print` / `parse` 往返：

- MoonBit `wasm` debug 与 release 产物
- MoonBit `wasm-gc` debug 与 release 产物
- 一个 `component`（由 `component_text` 生成）
- 一个截断/魔数错误的负数用例

## Reconsideration

若 `starshine` 修复 wasm 构建且其 `passes` 稳定，评估用其内嵌优化替代
`moon-wasm-opt` 进程调用；两者可并存，由 `--optimizer=moon|internal` 选择。

## Dependency Upgrade Verification (2026-11-11)

直接依赖升级到上表所列版本。新版本要求 MoonBit 0.10.20；使用 `moon`
0.1.20261104（moonc 0.10.20）完成验证。当前 `moon tree` 显示
`moonrockz/wit@0.4.0` 与本项目共用 `wasm_core` / `wasm_component@0.19.0`；本次
`moon check`、测试、release 构建及 CLI smoke 均通过。

升级验证命令：

```sh
moon tree
moon fmt
moon info
moon check --target all
moon test
moon test --target wasm
moon build --target wasm --release
moon build --target native
tests/smoke.sh
```
