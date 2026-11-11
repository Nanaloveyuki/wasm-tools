# 0010 WIT world 的 SemVer 兼容检查

- Status: Accepted
- Date: 2026-11-10
- Supersedes: 0006 中“Component/WIT 不进入当前数据模型”的后续阶段约束；Core ABI 模型保持不变。

## Context

Core ABI MVP 已验证。WIT 为 Component Model 用户提供比二进制外部名和 core 函数签名更高层的 package、world、interface 与资源类型边界，适合扩展当前的兼容分析主线。

现有 MoonBit 依赖 `moonrockz/wit` 提供 WIT parser 和纯语义 verifier。仓库所用 0.3.0 版本已公开解析、world 选择和解析后类型图 API；上游 v0.4.0 于 2026-11-08 发布，变更是 MoonBit 0.10.20 工具链升级，没有 API 变化。当前本地工具链为 0.10.19，因此首版继续使用可构建的 0.3.0。

WIT 的兼容判定不等于 Core ABI 的集合比较。Bytecode Alliance `wasm-tools` 的 `wit-component::semver_check` 以 Component Model 类型验证执行 WIT world 子类型检查：版本号不参与结构比较，候选 world 可增加 imports、减少 exports；同名项必须通过组件类型兼容关系。WIT 规范也定义 `@since`、`@unstable` 和 `@deprecated` 的语义，但首版不把 feature-gate 发布策略扩展成另一个 SemVer policy engine。

当前 `wasm_component/wit` 的 component 二进制 WIT 解码器文档限定为 type-only package shape，且实现是 best-effort：部分非目标 wrapper、奇数/越界 type index 会被跳过，一些不能恢复的类型会退化成 `other`。这对展示尽力恢复的 WIT 文本有用，但不能用来生成兼容快照，否则遗漏的接口会被误当成真实删除。不能据此承诺任意 component 二进制都能唯一恢复完整 source WIT 或自动选择目标 world。

## Decision

- 首版处理 WIT 源文件，并要求调用方显式选择 world；不从任意 Component 二进制自动猜测 source WIT、package 或 world。
- 提供可版本化的 WIT world snapshot 和 SemVer check API/CLI。契约身份包含 namespace、package 与 world 名称；package version 用于报告，但不作为结构兼容身份。
- `contract` 包拥有独立的 WIT snapshot 与报告类型，不暴露 `moonrockz/wit` 的解析器/AST 类型。`wasm` 边界调用 parser/verifier 并将已解析 world 规范化为本项目类型。
- 判定采用 Component Model 的 world 子类型方向：候选版本可增加 imports、删除 exports；删除 imports、增加 exports 为 breaking。首版不推导同名项内部的方差子类型，任何无法规范化的类型返回 `unknown`，可规范化但结构不同的同名项按 breaking 处理。
- 使用上游 `wasm-tools` 的公开算法和 WIT 规范作为语义参考及独立测试向量来源；不在运行时依赖其 Rust 工具或复制其实现代码。
- 当前不 vendor。若明确的上游缺陷或缺失能力阻塞已确定的验收路径，且已向上游报告、经过两个发布周期或 90 天仍无可用修复，可临时 vendor Apache-2.0 许可的最小源码子集。保留版权、许可证、来源版本、差异和回迁说明，并将 vendored 部分限制在必要修复范围；上游发布可用修复后，迁回依赖并删除本地副本。
- WIT source snapshot 与 check 是本阶段交付；Component 二进制 metadata 中 WIT 的选择/抽取作为单独后续议题，待出现稳定场景和可验证规则后再决定。
- Component 二进制快照必须等到提取完整性可以验证后再实现；不能直接把当前 best-effort decoder 的输出接入兼容比较器。后续议题：[Component 内嵌 WIT 契约提取完整性 #7](https://github.com/Nanaloveyuki/wasm-tools/issues/7) 正在跟踪上游 strict decoder 请求：[Milky2018/wasmoon#605](https://github.com/Milky2018/wasmoon/issues/605)。

## Consequences

- WIT 与 Core ABI 共享“快照、差异、breaking/unknown”产品形态，但保留分开的模型与兼容语义。
- WIT 兼容测试必须覆盖 package/world 身份、两种方向的新增/删除、相同名称类型变化、结构化类型与稳定快照。
- 首版不保留 `@since`/`@deprecated` 元数据，也不据此推导发布版本。解析时纳入全部 feature；带 `@unstable` 的 item 标为 `unknown`，带 feature gate 的 world 直接拒绝快照，避免把未选中的 feature 静默当成缺失接口。feature-aware 比较需要后续为选择策略建立明确 CLI/API 输入和快照身份。
- 当前依赖活跃维护且已有所需语法解析和语义验证能力，优先消费依赖 API；只有出现已证实的阻塞才评估 vendoring。

## Verification

- 基线与候选必须属于同一 namespace/package，且显式选择同名 world。
- 测试结果与 Component Model 子类型方向一致：增加候选 imports、移除候选 exports 可兼容；移除候选 imports、增加候选 exports 及同名类型变更为 breaking。
- 同一 WIT 仅改变 package version、源码空白或声明顺序时，兼容结论保持稳定。
- parser/verifier 拒绝或本项目无法规范化的语法不能被静默当作兼容。
- 可从 WIT 文件生成稳定 JSON 基线快照，并在 CLI 与 MoonBit API 两条路径运行检查。

## References

- [WebAssembly Component Model WIT specification](https://github.com/WebAssembly/component-model/blob/main/design/mvp/WIT.md#feature-gates)
- [Bytecode Alliance `wasm-tools` semver checker](https://github.com/bytecodealliance/wasm-tools/blob/main/crates/wit-component/src/semver_check.rs)
- [`moonrockz/wit` v0.4.0 release](https://github.com/moonrockz/wasm-devkit/releases/tag/v0.4.0)
- [`moonrockz/wasm-devkit` license](https://github.com/moonrockz/wasm-devkit/blob/main/LICENSE)
- [`moonrockz/wit` package API](https://mooncakes.io/docs/moonrockz/wit)
