# wasm-tools

面向 MoonBit WASM 发布产物的接口契约快照与兼容性检查工具。项目自有的契约模型、
快照格式和方向性比较器用于回答“新产物是否仍满足旧调用方/宿主的接口要求”；
这是项目的主要能力。解析与验证复用 MoonBit 生态依赖，本项目实现契约提取后的稳定
规范化、方向性兼容判定、差异报告和 fail-closed 结果；通用二进制命令作为辅助能力保留。
命令别名为 `wsm`。

模块只声明 wasm target；`moonx` 是本工具的正式入口。

## 安装与运行

```sh
# 无需安装，直接运行
moonx Nanaloveyuki/wasm-tools contract snapshot app.wasm -o app.abi.json
moonx Nanaloveyuki/wasm-tools contract check --baseline app.abi.json app-next.wasm --direction both

# 想要短命令，可以自己包一层
alias wsm='moonx Nanaloveyuki/wasm-tools'
wsm contract snapshot app.wasm -o app.abi.json
wsm contract check --baseline app.abi.json app-next.wasm --direction both
```

## 快速体验：检查 MoonBit 发布产物

运行完整演示：

```sh
./tests/contract-demo.sh
```

脚本用 MoonBit 编译器实际生成 `wasm` 与 `wasm-gc` 产物：基线导出两参数 `add`，同一
接口的跨目标产物应兼容；候选版本把 `add` 改为三参数，面向旧调用方的 `provided` 检查
应报告 breaking 并以退出码 1 结束。脚本会构建 CLI、生成快照并检查两种目标的结果，Linux
CI 也运行同一演示。

典型结果：

```text
provided: compatible
required: compatible
provided: breaking
  breaking  export add (function): export type changed
```

## 契约命令

主工作流围绕可提交、可复用的 JSON 基线：

```sh
wsm contract snapshot app.wasm -o app.abi.json
wsm contract check --baseline app.abi.json app-next.wasm --direction both
wsm contract wit snapshot --world cli app.wit -o app.wit.json
wsm contract wit check --world cli --baseline app.wit.json app-next.wit
```

| 命令 | 作用 |
|---|---|
| `contract snapshot [FILE]` | 从 Core WASM 模块生成确定性 ABI 快照 |
| `contract check --baseline SNAPSHOT FILE` | 按提供接口、依赖接口或两个方向比较兼容性 |
| `contract wit snapshot --world NAME [FILE]` | 从 WIT 源文件生成选定 world 的快照 |
| `contract wit check --world NAME --baseline SNAPSHOT FILE` | 比较 WIT world 的 SemVer 兼容性 |

比较输出区分 `provided`（新产物是否继续满足旧调用方）与 `required`（旧宿主能否满足新
产物的导入需求）。破坏性变化和当前无法安全比较的结构 `unknown` 都返回非零状态；调用方
可以据此阻止不安全发布或要求人工处理。

## 辅助 WASM 命令

| 命令 | 作用 |
|---|---|
| `validate [FILE]` | 自动识别 core module / component，解析并验证 |
| `print [FILE]` | 二进制转 WAT；component 按文档分段输出 |
| `parse [FILE]` | WAT / component WAT 转二进制 |
| `dump [FILE]` | section 表；`--instructions` 追加逐指令 offset，`--json` 输出结构化结果 |
| `strip [FILE]` | 删除 custom section；`--keep NAME` 保留指定段 |
| `metadata [FILE]` | 展示 `name` 与 `producers` custom section |
| `size [FILE]` | section、函数体大小与调用图；`--top N`、`--diff FILE`、`--budget SIZE`、`--json` |
| `opt [FILE]` | 调用 `moon-wasm-opt` 优化；`-O2`/`-Oz`、`--passes`、`--wasm-opt PATH` |
| `symbolize [FILE] ADDR` | 把 `wasm-function[N]:0xOFF` 映射到函数名与函数内偏移 |
| `component wit [FILE]` | 从 component 提取内嵌 WIT 包 |

通用约定：

- 输入缺省为 stdin，`-` 也表示 stdin；`-o FILE` 指定输出文件。
- 二进制输出默认写 stdout，重定向由调用方负责（当前没有可移植的 isatty）。
- 退出码：`0` 兼容/成功，`1` 内容非法、breaking 或 unknown，`2` 用法、IO 或快照 schema 错误。

```sh
wsm parse app.wat -o app.wasm
wsm validate app.wasm
wsm print app.wasm -o app.wat
wsm dump --instructions app.wasm | head
wsm strip app.wasm --keep producers -o app.stripped.wasm
wsm metadata --json app.wasm
wsm size app.wasm --top 20
wsm size app.wasm --diff old.wasm
wsm size app.wasm --budget 200KB
wsm opt app.wasm -Oz -o app.opt.wasm
wsm symbolize app.wasm 'wasm-function[34]:0xd8d'
wsm symbolize --json app.wasm 0xd8d
cat app.wasm | wsm validate -
```

## 范围

契约命令：

- `contract snapshot FILE` 输出带 `format_version` 的稳定 JSON；接口按名称、种类及结构化类型表示，不用 WASM 类型索引作为身份。
- `contract check --baseline BASELINE FILE` 输出逐项变化。`provided` 检查候选产物能否继续满足旧调用方；`required` 检查旧宿主能否满足候选产物的新导入需求；默认 `both` 分开报告两个方向。
- `breaking` 与 `unknown` 均默认返回退出码 1。带类型化引用等当前无法安全比较的接口会报告 `unknown`，不会静默判兼容。
- Core ABI MVP 支持 `wasm` 与 `wasm-gc` 产物。WIT MVP 直接处理 WIT 源文件并要求显式选择 world；它不从任意 Component 二进制推断 package/world，也不覆盖 Component 二进制中的 WIT 抽取。未能安全规范化的 WIT 结构返回 `unknown`。
- WIT world 比较忽略 package 版本与源码声明顺序；候选 world 增加 imports、移除 exports 可兼容，移除 imports、增加 exports 或改变同名项类型为 breaking。首版不推导同名项内部的方差子类型；未能规范化或受 `@unstable` gate 影响的 item 返回 `unknown`，带 gate 的 world 无法快照。
- `contract` 包提供与 CLI/解析器类型无关的快照和比较 API；`wasm` 包负责把二进制解析结果规范化为该模型。

```moonbit
let old_snapshot = @contract.parse_snapshot(baseline_json)
let new_snapshot = @wasm.contract_snapshot(candidate_bytes)
let report = @contract.compare_snapshots(
  old_snapshot,
  new_snapshot,
  @contract.Both,
)
```

## 实现边界与独立贡献

- `contract` 包定义独立于 CLI 和上游 AST 的契约模型、版本化快照、稳定身份与兼容报告。
- `wasm` 适配层把解析出的外部类型规范化为项目模型；类型段索引和无关 section 顺序不作为
  ABI 身份。
- 本项目实现 `provided` / `required` 方向规则、变化分类和 `breaking` / `unknown` 判定。未
  建模的结构明确报告 `unknown`，不会因解析成功就默认兼容。
- Core WASM 的真实 `wasm` / `wasm-gc` 产物以及 WIT 源文件均有快照和兼容检查路径；演示脚本
  与单元测试覆盖这些结果。

解析/验证与项目自研逻辑的边界如下：

- core module 走 `Milky2018/wasm_core`（解析、验证、WAT 双向、编码）
- component 走 `Milky2018/wasm_component`（解析、验证、WIT）
- component → WAT 走 `moonrockz/wit/decompiler`
- WIT/WAC 通用 parse/format/verify 交给 `moonx moonrockz/wasm-devkit`；WIT 契约命令复用 `moonrockz/wit` parser/verifier API 并使用项目自有的快照与比较模型
- 优化交给工具链自带的 `moon-wasm-opt`；`opt` 只做参数映射与产物校验，不实现 pass

通用命令是生态库能力的入口与集成，不计作契约分析的独立贡献。不做：运行时/JIT、优化 pass、
WIT/WAC 语言工具、`smith`/`mutate`/`shrink`、
`component new`/`embed`。设计理由见 [docs/adr](docs/adr/README.md)。

`dump`/`metadata` 对 component 使用独立的 section id 表；`size` 对 component
只报告 section 明细，函数与调用图仅对 core module 有效。

## 状态

| 项目 | 值 |
|---|---|
| Mooncakes | 已发布 `Nanaloveyuki/wasm-tools@0.4.2`；工作树版本 `0.5.0` 尚未发布 |
| CI | GitHub Actions，Ubuntu / macOS / Windows 三平台 |
| 测试 | 单元测试 + Linux CLI / MoonBit 产物演示 + Windows CLI（moonrun interop） |
| 许可证 | Apache-2.0 |

## 路线

| 版本 | 内容 |
|---|---|
| 0.1.0 | validate / print / parse / dump / strip / metadata / component wit |
| 0.2.0 | component 感知的 dump/metadata；`size` v1（section、函数、调用图） |
| 0.3.0 | `opt`（包装 `moon-wasm-opt`）；`size --diff`/`--budget` |
| 0.4.2（当前） | `symbolize`（name section 符号化）；`compose` 因上游依赖阻塞 |
| 0.5.0（当前开发） | Core ABI 与显式 WIT world 快照、方向性兼容检查及 WIT SemVer 检查 |

详细决策与验证标准见 [ADR 索引](docs/adr/README.md)。

## 开发

```sh
moon build --target wasm       # 生成 _build/wasm/debug/build/wasm-tools.wasm
moon check --target all        # 检查所有支持的编译后端
moon test                      # 单元测试
./tests/contract-demo.sh       # 真实 wasm / wasm-gc 契约兼容演示
./tests/smoke.sh               # CLI 行为检查（Linux）
tests/win-smoke.sh             # Windows 侧检查（WSL interop，需 WIN_MOONRUN/WIN_WASM_OPT）
```

`./run.sh` 用本地 wasm 构建运行 CLI。契约演示可以独立运行；`tests/smoke.sh` 也会运行该演示，
再覆盖 WIT 源文件到 world 快照的 CLI 路径。

## 结构

```text
main.mbt          argv 转发与退出码
cli/              参数、IO、帮助、错误（不依赖 wasm 包）
cmd/              每个子命令一个文件
contract/         契约领域模型、稳定快照、方向性比较器
wasm/             raw 扫描与上游解析器适配，包括契约提取
tests/            fixtures、cli.md 场景、smoke.sh
examples/         导出 add ABI 的 MoonBit foreign library 样例与 breaking 变体
docs/adr/         范围、依赖与发布决策
```

依赖方向为 `main → cmd → wasm/contract → 上游包`。`contract` 不依赖 CLI、命令层
或上游 AST；`wasm` 是解析器边界，`cmd` 负责参数和输出。
