# ADR

本目录记录 `wasm-tools` 的架构与范围决策。新决策使用递增编号，旧 ADR 标记
`Superseded by NNNN` 而不是删除。

| 编号 | 决策 |
|---|---|
| [0001](0001-cli-scope.md) | CLI 定位、首版命令面与非目标 |
| [0002](0002-dependency-selection.md) | 依赖选择、实测边界与上游协作 |
| [0003](0003-module-layout-and-delivery.md) | 模块布局、moonx 发布约束与交付顺序 |
| [0004](0004-post-0.1-roadmap.md) | 0.2.0–0.4.0：component 结构、size、opt、compose、addr2line |

## 写法

- 只记录需要跨文件、跨会话保持一致的决策，不记录临时调研过程。
- “Context”写为什么现在需要这个决策；“Decision”写不可再推导的约束；
  “Verification”写如何证明决策仍然成立。
- 依赖版本和实测结论必须带日期，升级依赖时追加新 ADR 或更新对应条目。
