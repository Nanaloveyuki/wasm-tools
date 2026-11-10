# 0008 契约快照格式与 CLI 约定

- Status: Accepted
- Date: 2026-11-10

## Context

CI 比较需要能被提交、归档和跨版本读取的基线格式；用户也需要一条最短路径从真实 WASM 产物生成基线并检查候选产物。现有 CLI 将内容错误和用法/IO 错误分开，新增命令应延续这一约定。

## Decision

- 提供 `wsm contract snapshot FILE` 和 `wsm contract check --baseline BASELINE FILE [--direction provided|required|both] [--json]`。
- 快照输出为确定性 JSON，包含独立的 `format_version`。数组使用稳定排序；对象字段顺序及格式化固定。非语义性的 section 顺序、custom section 和文件路径不参与契约相等性。
- 快照是可读的结构化描述，不只是 hash；比较报告逐条列出接口变化，以便 CI 日志和代码评审理解原因。
- `format_version` 表示快照 schema 版本。无法读取的未来 schema 版本应明确失败，不得猜测字段语义。
- `snapshot` 默认将 JSON 写入 stdout，允许 `-o FILE` 写到文件；`check` 默认输出人类可读差异，`--json` 输出机器可读报告。
- 退出码遵循现有约定：`0` 表示所有请求方向均兼容，`1` 表示 breaking/unknown 或 WASM 内容无效，`2` 表示参数、文件 IO 或 schema 版本错误。
- 初版不提供自动忽略规则、豁免配置、推荐 semver 版本或 SARIF；这些需求在基础报告被真实 CI 使用后再决定。

## Consequences

- 需维护快照 schema 示例和版本演进规则，并测试稳定序列化。
- 文件路径可作为报告上下文，但不得影响同一契约的稳定比较。
- 对 CI 而言，默认 fail-closed；本地使用者可先通过报告诊断 `unknown`，后续再讨论显式豁免机制。

## Verification

- 同一契约重复生成的 JSON 字节级一致；重新排列无关 section 不改变快照语义。
- `snapshot` stdout、`-o` 文件输出、文本报告、JSON 报告及三类退出状态均有 CLI 覆盖。
- 对不支持的快照 schema，错误清楚且退出码为 `2`。
