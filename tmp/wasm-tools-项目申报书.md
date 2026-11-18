# wasm-tools 项目申报书

- 项目名称：wasm-tools：面向 GitHub Actions 的 WASM 发布包一致性检查
- 参赛者：Nanaloveyuki
- GitHub 仓库：https://github.com/Nanaloveyuki/wasm-tools
- 项目方向：MoonBit 开发工具 / 发布工程与持续集成
- 项目类型：原创发布包检查工具；解析、ABI、压缩解码和执行复用生态能力。
- 联系方式：19139950568

## 项目简介
面向发布 MoonBit WASM 库与应用的维护者，检查即将发布的目录中 loader、Worker、WASM 和压缩副本是否齐全、一致、可消费。用户提交显式文件清单，在本地或 GitHub Action 中识别漏发依赖、旧版 gzip/Brotli 副本及实际入口失败；报告包含文件 SHA-256、逐项结果和失败原因。

## 核心功能与 MoonBit 实现职责
- MoonBit 严格解析版本化清单，校验相对路径、大小写重复、文件/目录冲突及消费者/压缩源引用；拒绝未知字段、重复 key、错误类型与悬空引用。
- 逐文件捕获字节、检查普通文件与符号链接并计算 SHA-256；Core 验证委托已有库。后续解压比对和每个独立消费副本使用同一批捕获字节，不重读源文件。
- 声明 gzip/br 与 identity 原件的关系，调用 Node 标准库有限解压，再由 MoonBit 逐字节比较；损坏、过期、尾随或超限副本阻止通过。
- 每个消费者仅复制声明文件到新目录，在独立 Node 进程调用声明的 ESM 导出；MoonBit 比较 JSON 期望，区分缺文件、异常、无结果、结果不符和超时，验证真实 WASM 与 Worker 加载。
- 提供 bundle check、JSON/Markdown 报告与 Linux composite Action；Action 负责安装、启动、Job Summary 和输出适配，清单语义、字节比较、期望判定与失败聚合由 MoonBit 实现。

## 相似项目对比与复用关系
- [MoonHostABI b2fcd60](https://github.com/0717lee/moonhostabi/blob/b2fcd602b68b240b2fcd29a0759b7cd6cfb11c23/docs/consumer-example.md) 已有 ABI/生成适配器及真实消费、隔离安装测试。本项目的既有 release 流程调用其 native verify 并校验报告和候选哈希；新增检查整个声明发布目录、压缩副本与指定 ESM/Worker 消费，不另建 ABI 比较或适配器生成器。
- [moonsize 9499de8](https://github.com/BigSaltyMan/moonsize/tree/9499de8557a3bf529f857e4df01edd2342151632) 与 [wasmslim 0.3.1](https://mooncakes.io/docs/zhangbowen2006/wasmslim@0.3.1) 已有体积预算、归因与 CI 场景；本项目不以这些能力作为差异，重点比对磁盘上的实际压缩副本及发布文件消费结果。
- [Wasmoon 2e98651](https://github.com/Milky2018/wasmoon/tree/2e986517249e056026a84479b48af41a15f5ee88) 已有解析验证、WAT/WIT、运行测试和自身 CI；所查 Git 树无 Action metadata。解析验证复用其生态库；旧自有 Core/WIT 契约命令仅兼容保留，不计入独立贡献或新流程 ABI 回退。

## 验证、交付与边界
- 已交付 MoonBit bundle API、CLI、Action、真实 MoonBit WASM/Worker 示例、回归用例与 ADR；既有 release 策略/处理和 MoonHostABI 桥接作为辅助能力，采用 Apache-2.0。
- 分阶段验证文件与引用、gzip/br 一致性、干净目录消费后再接入 Action；回归覆盖漏发、旧副本、损坏、超限、伪造日志、错误结果、用例污染、同步/异步超时及报告失败恢复。
- 源码为未发布的 0.6.0 开发版，已发布 0.5.1 不含 bundle/release；CI 固定 Node 20，覆盖三平台消费和 Linux 完整 Action，远端结果以对应提交运行记录为准。
- 首版文件上限 256/64 MiB、消费者上限 16；WASM 路径限 Core，消费入口限 Node ESM，Action 限 Linux；不宣称安全沙箱、浏览器覆盖、依赖自动推断、npm/OCI 打包或行为等价证明。
- 后续维护真实发布案例、工具链与上游协议适配，不扩建运行时、优化器或自有 Core ABI 主线。
