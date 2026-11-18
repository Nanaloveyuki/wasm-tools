# wasm-tools 项目申报书

- 项目名称：wasm-tools：面向 GitHub Actions 的 WASM 发布检查与产物处理
- 参赛者：Nanaloveyuki
- GitHub 仓库：https://github.com/Nanaloveyuki/wasm-tools
- 项目方向：MoonBit 开发工具 / 发布工程与持续集成
- 项目类型：原创发布规则与处理工具；解析、验证、优化和 Core ABI 比较复用现有生态能力。
- 联系方式：19139950568

## 项目简介
面向发布 MoonBit WASM 的库和应用维护者，将“构建成功”进一步检查为“最终产物符合仓库的发布规则”。用户提交一份配置，即可在本地或 GitHub Action 中检查多个产物的体积、增长预算、宿主导入和 custom section，按配置清理或优化后复检，输出报告与通过检查的待发布文件。

## 核心功能与 MoonBit 实现职责
- 严格解析版本化 JSON 配置，拒绝未知字段、重复 key、错误预算与规则冲突；提供不依赖 CLI、IO 或解析器 AST 的 MoonBit `release` API。
- 实现总字节、相对基线增长量/百分比及 section 预算；同名段合计且包含段头，增长使用整数比较；精确检查 import allowlist 和 custom section 保留/禁止规则。
- 提供 `release check` 与 `release prepare`：原件验证、精确剥除指定段、可选优化、最终字节验证与同规复检；上一版最终 WASM 基线只读，不参与本次处理。
- 批次全部通过后才发布到新的输出目录；既有目录不覆盖，检查或报告失败回滚本次输出，并保护输入和基线。JSON 保留处理前后/基线事实与 SHA-256，Markdown 展示增长来源和失败原因。
- 提供 Linux composite Action，负责工具安装、CLI 调用、Job Summary 和输出路径适配；规则求值、比较、处理流程和报告主体由 MoonBit 实现。

## 相似项目对比与复用关系
- [Wasmoon 0.19.0 / main@40379a3](https://github.com/Milky2018/wasmoon/tree/40379a3b7bde338ebb1dbbbb7822a7e3a92daab8) 已提供解析验证、WAT/WIT 工具、运行测试和自身 CI；所查提交没有 Action metadata 或 workflow_call。项目差异在用户发布产物的配置化规则、增长预算、处理后复检与输出发布，不以 CI、批量执行或 JSON 本身作为独立贡献。
- [MoonHostABI](https://github.com/0717lee/moonhostabi) 负责 Core ABI 规范化、lock 与兼容性结论。本项目真实调用其 native `verify --format json`，保留原始报告并核对协议、退出码与候选哈希；安装器及集成验证固定 0.6.0，未知或不兼容结果阻止通过，不实现另一套 ABI 比较回退。
- 解析验证复用 `Milky2018/wasm_core` 等库，优化调用 `moon-wasm-opt`。已发布的自有 Core/WIT 契约命令仅兼容保留，不进入新 Action 的 ABI 判定，也不计入本次独立贡献。

## 实现、验证与交付
- 已完成 MoonBit 规则库、事实提取、检查/处理 CLI、MoonHostABI 桥接、JSON/Markdown 报告、Action、真实 MoonBit 示例、回归用例及 ADR；采用 Apache-2.0 许可。
- 源码版本为 0.6.0 开发版，尚未声明发布到 Mooncakes；原有已发布 0.5.1 包不含本次 release 命令。远端 CI 结果以对应提交的运行记录为准。
- 本地验证：全目标 deny-warn 检查通过；wasm 58 项、wasm-gc/JS/native 各 25 项测试通过；原 CLI 回归、真实 MoonHostABI 兼容/破坏性变化、真实优化、失败回滚和 Action 安装/调用通过；actionlint 及发布 dry-run 预检通过。
- 当前发布路径限 Core WASM，Action 首版限 Linux；不提供递归 Component 策略、运行时资源隔离或行为等价证明。外部 CLI 覆盖按已知报告协议校验，不检查版本字符串。
- 后续优先维护实际发布用例、固定工具链和上游协议适配；不扩建运行时、优化器或自有 Core ABI 比较主线。
