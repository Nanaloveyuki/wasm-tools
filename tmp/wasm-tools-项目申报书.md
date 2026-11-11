# wasm-tools 项目申报书

## 基本信息
- 项目名称：wasm-tools：MoonBit WASM 契约快照与兼容性分析
- 参赛者：Nanaloveyuki
- GitHub 仓库：https://github.com/Nanaloveyuki/wasm-tools
- 项目方向：MoonBit 开发工具 / WebAssembly 契约兼容性分析
- 项目类型：原创项目；依赖 MoonBit WASM 与 WIT 生态库完成解析和验证，不是上游工具的移植。
## 项目简介
MoonBit 库升级时，编译生成的 WASM 导入和导出接口可能发生变化，而源码 diff 无法直接说明下游调用方或宿主是否仍兼容。wasm-tools 将真实 WASM 产物规范化为可提交、可复查的接口快照，并对新旧版本给出方向明确、可用于 CI 的兼容结论。

## 核心功能与技术贡献
- 为 Core WASM 定义独立于解析器 AST 和 CLI 的契约模型、版本化稳定 JSON 快照及 MoonBit API。
- 从 MoonBit `wasm` / `wasm-gc` 产物提取 import/export 名称、种类和受支持的结构化类型；不以类型索引或无关 section 顺序作为接口身份。
- 实现 `provided`（新版本继续满足旧调用方）与 `required`（旧宿主满足新导入需求）两种方向的兼容比较，逐项解释 breaking 变化；无法安全建模的类型以 `unknown` 失败关闭。
- 支持指定 WIT world 生成快照并按 Component Model 的 imports/exports 方向规则比较；版本号、空白和声明顺序变化不改变结构比较结果。
- 提供 `wsm contract snapshot/check` CLI；快照可保存、审阅并在发布流水线中复用，breaking/unknown 返回非零退出码。
- 独立实现集中于契约领域模型、规范化、稳定快照、比较规则和差异报告；上游依赖负责 WASM/WIT 解析与验证，本项目不重复实现二进制解析器。
## 实现、验证与交付
- 已完成 Core ABI 与 WIT 源文件的快照和兼容检查、通用 WASM 辅助命令、用户文档及 Apache-2.0 许可。
- `./tests/contract-demo.sh` 从 MoonBit 源码构建真实 `wasm` / `wasm-gc` 产物，验证跨目标 ABI 兼容及函数签名变化被判为 breaking。
- 当前验证：`moon check --target all` 通过；38 项 MoonBit 测试通过；Linux CLI smoke、WASM release 构建及 Mooncakes 发布包 dry-run 通过。CI 覆盖 Ubuntu、macOS、Windows 构建与测试，并在 Linux 运行端到端演示。
- 交付物：公开 GitHub 仓库、Mooncakes `Nanaloveyuki/wasm-tools` 包、可复用 MoonBit API、`wsm` CLI、示例、测试与 ADR。

## 当前边界与后续工作
- Component 二进制内嵌 WIT 暂不生成兼容快照：现有上游解码器是 best-effort，可能跳过或降级类型，无法证明接口提取完整；项目已向上游提交 strict decoder 议题并跟踪修复。完整性可验证后再接入比较器。
- WIT 首版要求显式指定 world，不从任意 Component 二进制推断 package/world；feature-gate 策略与 `@since` / `@deprecated` 发布策略尚未纳入。
- 同名 WIT 类型采用精确结构比较，暂不推导函数参数/结果方差或聚合类型宽度兼容；超出已建模范围的类型报告 `unknown`。
- `addr2line` 暂不支持：当前 MoonBit WASM 产物没有 DWARF 数据源；已有 `symbolize` 可依据 name section 定位函数名和函数内偏移。
- 后续围绕真实用户反馈扩展可比较类型、完善 Component WIT 完整性支持，并评估 CI 报告集成；保持未知情况显式可见。
