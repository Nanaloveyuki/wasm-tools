# 0011 WIT 深层透明别名规范化

- Status: Accepted
- Date: 2026-11-11
- Complements: 0010

## Context

WIT snapshot 将解析后的类型图规范化为结构签名。现有 `wit_type_key` 用同一个
递归深度计数处理结构嵌套和透明 alias 链，超过 256 层就将该签名标为 `unknown`。
这会拒绝上游 verifier 已验证的长 alias 链，即使链最终指向普通标量类型。

`moonrockz/wit@0.4.0` 的 verifier 测试覆盖了 5000 节点的 alias 链，并验证它能通过；
因此 256 是本项目规范化器的限制，不是 WIT verifier 的输入边界。

## Decision

- WIT alias 透明地指向其最终类型，不构成独立结构。任意受支持长度的合法 alias
  链应规范化为同一底层类型；底层结构相同则兼容，底层结构变化仍为 breaking。
- alias 遍历使用迭代路径压缩，不消耗结构嵌套深度预算。结构构造器的递归深度仍
  限制为 256；单条 alias 链最多处理 65536 个节点，超限、缺失目标或不稳定类型
  fail-closed 为 `unknown`。
- 此规则扩展可比较的合法 WIT 输入范围，不扩展 Component Model 子类型关系；同名
  类型仍按 ADR 0010 的精确结构规则比较，不推导函数方差或聚合类型宽度兼容。

## Verification

- Golden case 使用 1024 节点 alias 链：同一终端类型的直达 alias 与长链比较为
  `compatible`；仅把终端从 `u32` 改为 `u64` 比较为 `breaking`，并确认快照未产生
  `unknown:` 签名。
- 固定 seed `20261113` 的属性测试在 257–289 节点范围生成不同 alias shortcut
  路径，检查规范化签名可比较且结果保持 `compatible`。
- 上游依据：[`moonrockz/wit@0.4.0` verifier test](https://github.com/moonrockz/wasm-devkit/blob/v0.4.0/pkgs/wit/src/verifier/verify_test.mbt#L90-L102)
  的 “long alias chains and cycles use bounded explicit work stacks” 测试验证
  5000 节点 alias 链通过、循环 alias 被拒绝。
