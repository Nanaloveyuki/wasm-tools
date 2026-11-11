# 0009 契约检查器的验证与交付标准

- Status: Accepted
- Date: 2026-11-10

## Context

新主线必须证明的是兼容性结论和 CI 使用价值，而不仅是命令可运行。只有手写 JSON 快照的单元测试无法覆盖从真实 MoonBit 编译产物提取契约的整条路径。

## Decision

- 以领域比较测试、解析/规范化测试和端到端 CLI 测试分层验证；测试应分别证明兼容方向、未知类型处理、稳定快照及退出码。
- 提供最小的 MoonBit 源码样例，构建为 `wasm` 与 `wasm-gc` 产物，生成快照并演示一次兼容升级和一次破坏性变更。
- 将最小契约检查加入仓库 CI；CI 执行 `moon check`、`moon test`、wasm release 构建与 CLI 集成样例。
- 记录支持范围和 `unknown` 原因。只对实际覆盖并通过测试的 WASM 类型宣称支持；不得把解析器接受输入等同于比较器理解其 ABI。
- 对声明顺序、package version 等按规范应忽略的变化建立固定种子的属性测试；测试直接构造快照，覆盖规范化构造器之外的比较与序列化边界。
- WIT 方向与同名类型变化的预期结果应对照 [ADR 0010 固定的上游语义来源](0010-wit-semver-compatibility.md)；属性测试补充排列不变性，不替代这些有明确预期值的案例。
- WIT 类型规范化覆盖上游 verifier 接受的长透明 alias 链；链路差异但终端类型相同应有相同结构签名，终端类型改变应保留 breaking 结果。
- 当前阶段不要求性能基准或模糊测试作为发布门槛；输入解析边界测试需覆盖损坏、截断和不支持的结构。
- 发布说明、README、Mooncakes 描述与能力状态同步更新。契约功能未在发布资产中可用前，不将其描述为已交付能力。

## Verification

- 干净检出后可按 README 的命令完成检查、构建、测试和示例。
- CI 能以真实 `wasm` / `wasm-gc` 产物覆盖 snapshot→check 流程。
- 负例稳定返回非零状态并输出可定位的原因；支持范围外的输入不会误判为兼容。

## Work breakdown

实施议题已创建：
[契约领域模型 #1](https://github.com/Nanaloveyuki/wasm-tools/issues/1)、
[Core WASM 提取 #2](https://github.com/Nanaloveyuki/wasm-tools/issues/2)、
[兼容比较器 #3](https://github.com/Nanaloveyuki/wasm-tools/issues/3)、
[快照 CLI #4](https://github.com/Nanaloveyuki/wasm-tools/issues/4)、
[真实产物与 CI #5](https://github.com/Nanaloveyuki/wasm-tools/issues/5) 和
[Component/WIT 后续评估 #6](https://github.com/Nanaloveyuki/wasm-tools/issues/6)。
