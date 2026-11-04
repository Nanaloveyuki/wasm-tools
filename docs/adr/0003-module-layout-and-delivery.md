# 0003 模块布局、moonx 发布约束与交付顺序

- Status: Accepted
- Date: 2026-11-04
- Supersedes: —

## Context

`moonx` 不编译源码，只下载并运行 MoonCakes 上已构建的 wasm 资产。实测
`moonx BigSaltyMan/moonsize` 报 `Prebuilt wasm asset does not exist`，而
`moonx moonrockz/wasm-devkit` 正常，两者差别正是模块是否声明并能构建 wasm
可执行包。因此布局必须围绕“一个可执行的 wasm 入口”设计，而不是普通的库布局。

资产地址由 Moon 的 registry client 拼接：

```text
https://download.mooncakes.io/prebuild/<module>@<version>/<package-path>/<stem>.wasm
https://download.mooncakes.io/prebuild/<module>@<version>/<package-path>/<stem>.wasm.sha256
```

根包（`package-path` 为空）的 `stem` 取模块最后一段。所以 `<namespace>/wasm-tools`
的根包可执行文件会发布为 `wasm-tools.wasm`，`moonx` 坐标就是
`moonx <namespace>/wasm-tools`。

## Decision

### 仓库布局

```text
moon.mod                     # <namespace>/wasm-tools
moon.pkg                     # executable; imports cmd; native+wasm
main.mbt                     # 只做 argv 转发与退出码
cli/                         # 参数解析、帮助、错误渲染、IO 约定
cmd/                         # 每个子命令一个文件
  validate.mbt
  print.mbt
  parse.mbt
  dump.mbt
  strip.mbt
  metadata.mbt
  component.mbt
wasm/                        # 唯一允许出现外部库类型的层
  core.mbt                   # wasm_core 适配
  component.mbt              # wasm_component 适配
  wat.mbt                    # core/component 文本与二进制互转
  raw.mbt                    # section 扫描、LEB128、custom section
  dump.mbt                   # section/instruction 报告
  strip.mbt                  # custom section 过滤
  metadata.mbt               # name/producers
tests/                       # 每个子命令的 cram 风格 CLI 测试
  cli/*.md
```

依赖方向固定为 `main → cmd → wasm → 外部包`。`cli` 可以被 `cmd` 依赖，但不得
依赖 `wasm`；`wasm` 不得依赖 `cmd`。这条规则保证命令层可替换、适配层可单测。

### 发布配置

`moon.mod` 至少包含：

```text
name = "<namespace>/wasm-tools"
preferred_target = "wasm"
import { "Milky2018/wasm_core@0.18.0", ... }
```

根 `moon.pkg`：

```text
import { "Nanaloveyuki/wasm-tools/cmd" }
supported_targets = "native+wasm"
pkgtype(kind: "executable")
```

根包可执行决定了 `moon install` 与 `moonx` 的名字都是模块最后一段 `wasm-tools`；
`wsm` 是 usage/help 中的命令名，native 安装后可用 `alias wsm=wasm-tools`。

`moon publish` 之后必须确认 `build_status` 为 success，并实际执行
`moonx <namespace>/wasm-tools --help`；如果资产缺失，说明根包不是可执行包或
wasm 目标构建失败，需要在发布前修复，而不是靠用户本地编译兜底。

### 交付顺序

| 里程碑 | 交付 | 通过条件 |
|---|---|---|
| M0 ✅ | 模块骨架、帮助、`--version`、CI（wasm+native 构建） | `moon build` 两种目标通过；`moon publish --dry-run` 通过 |
| M1 ✅ | `validate`、`print`、`parse` | MoonBit `wasm`/`wasm-gc` 产物验证通过；`parse(print(x))` 语义等价；负例退出码为 1 |
| M2 ✅ | `dump`、`strip`、`metadata` | section 偏移/大小与原始字节一致；`strip` 后仍可验证；`--json` 字段稳定 |
| M3 ◐ | component `print`、`component wit` | 组件 WAT 多文档输出；`component wit` 对无 WIT 的组件给出 Unsupported；尚缺带 WIT 的真实固件 |
| M4（另立 ADR） | `size`、`compose`、`opt`、`addr2line` | 体积报告可作为 CI 门禁；WAC 组合结果可验证；`opt -Oz` 输出可验证 |

M4 不进入首版，避免把 CLI 骨架、raw 层、组件层、优化桥一次性耦合。
发布 0.1.0 属于 M0 的人工步骤，需要在确认后执行：`moon publish`。

### 测试策略

- **单元测试**：`raw` 的 LEB128/section 边界；`strip` 的保留/删除组合；
  `metadata` 的 name/producers 解析。
- **CLI 测试**：使用 `moonbitlang/core` 的 expect 测试与 cram 风格脚本，
  覆盖 stdin、`-`、`-o`、tty 拒绝、退出码。
- **差分测试**：CI 里安装上游 `wasm-tools`，对同一批固件比较
  `validate` 的接受/拒绝、`print` 再次 `parse` 后的语义等价、`strip` 后 section
  集合。上游只作为测试依赖，不进入运行时。
- **真实产物**：CI 额外构建两个最小 MoonBit 包，分别产出 `wasm` 与 `wasm-gc`，
  作为固件来源，避免只用自造模块导致“自证”。

### 风险

| 风险 | 应对 |
|---|---|
| 根包改成库后 moonx 资产消失 | CI 在发布后跑 `moonx` 冒烟；发布清单里固定检查资产 URL |
| 上游依赖 API 漂移导致无法构建 | 精确 pin；每次升级跑 `moon build --target wasm` 与固件回归 |
| 组件路径依赖 `moonrockz/wit` 的 core 解析上限 | core 模块永远走 `wasm_core`；组件反编译失败时降级为“只输出组件结构”并给上游 issue |
| `opt` 依赖宿主 spawn 权限 | 显式检测并提示；native 安装作为兜底 |
| 单二进制体积增长 | 首版预估 2–3MB；超过 6MB 时再按子命令拆模块 |

## Consequences

- 首版只有一条发布单元，版本与资产一一对应，用户不需要理解包路径。
- 命令全部集中在一个 wasm 里，后续拆包会带来坐标变化，因此拆分必须由新 ADR 决定。
- `wasm-devkit` 继续作为 WIT/WAC 的入口，文档与 `--help` 中直接给出对应命令，
  不复制其功能。

## Verification

M0 完成后执行并记录：

```sh
moon build --target wasm --release
moon build --target native --release
moon test
moon publish --dry-run
moonx <namespace>/wasm-tools --help
```

资产地址可直接检查：

```sh
curl -I https://download.mooncakes.io/prebuild/<namespace>/wasm-tools@<version>/wasm-tools.wasm
```

## Reconsideration

如果后续同时存在“只想验证”与“需要完整工具”的两类用户，再评估拆成
`wasm-validate` 与 `wasm-tools` 两个模块；拆分前保持单模块。
