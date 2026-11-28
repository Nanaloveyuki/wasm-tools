# 贡献指南

本文记录源码构建、测试、架构边界及生态分工。安装、CLI 和 GitHub Action 用法见 [README](README.md)。架构决策和分阶段验收记录见 [ADR 索引](docs/adr/README.md)。项目采用 [Apache-2.0](LICENSE) 许可。

## 从源码构建

本地和 Action 使用 `.moonbit-toolchain` 固定的编译器归档。以下示例使用 Unix 安装器。

```sh
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- "$(cat .moonbit-toolchain)"
export PATH="$HOME/.moon/bin:$PATH"
moon update
moon build --target wasm --release
```

以下命令用 Node.js 20 或更新版本运行包含 MoonBit WASM、loader、Worker 和压缩副本的示例。

```sh
bundle_example="$(mktemp -d)"
node scripts/make-bundle-example.mjs "$bundle_example/release"
moonrun _build/wasm/release/build/wasm-tools.wasm -- bundle check "$bundle_example/release/bundle.json" \
  -o "$bundle_example/report.json" --summary "$bundle_example/report.md"
```

示例读取本仓库编译出的 `examples.wasm`，分别在主线程和 Worker 调用 MoonBit 的 `add(20, 22)`，两者都必须得到 `42`。生成器只写新目录，发布清单放在包目录之外。手动替换 `package/calculator.wasm.gz` 为其他版本的副本，即可观察压缩一致性失败。

## 开发与验证

```sh
moon check --target all --deny-warn
moon test --target all --deny-warn
moon fmt
moon info
moon build --target wasm
./tests/smoke.sh
MOONHOSTABI=moonhostabi python3 tests/release-check.py
python3 tests/bundle-check.py
WSM_CLI_WASM="$PWD/_build/wasm/debug/build/wasm-tools.wasm" node tests/action-runner.mjs
```

发布集成用例覆盖预算边界、重复段、规则负例、真实优化、基线不变、批次失败不发布、报告失败回滚及文件别名保护。设置 `MOONHOSTABI` 或将工具加入 PATH 时，运行真实兼容及破坏性变更和处理后 ABI 检查。缺少工具时测试输出会标记 ABI 集成为跳过。

发布包回归使用真实 zlib 流和 WASM/Worker，覆盖陈旧/损坏/尾随/超限压缩数据、漏发依赖、用例间污染、伪造日志、非 JSON 返回、同步/异步超时、大参数传输及结果上限。

CI 固定 Node 20，包含三平台构建/消费测试、Linux 完整 Action 安装与调用、真实 MoonHostABI 委托，以及有意失败的预算和过期压缩副本。远端执行结果以对应提交的 Actions run 为准。

## 运行机制

- Bundle 捕获每个声明文件一次，哈希、解压比对和消费快照使用同一份字节。Node 标准库负责解码，MoonBit 逐字节比较原件。解码以原件长度加一为上限，并核对解码器消费了全部输入。
- npm 归档在内存中读取。压缩输入和解压后的 tar 各限 72 MiB，普通文件内容合计限 64 MiB，tar 头最多 4096 个。读取器支持 USTAR、逐条目的 PAX 元数据和 GNU 长文件名。
- 每个消费用例使用新的目录和子进程。环境保留 `PATH`、系统路径与临时目录变量，参数通过 JSON 请求文件传入。临时快照避开具有 Node 包配置或依赖的祖先目录，Node 全局包查找关闭。stdout、stderr 和 JSON 结果分开捕获，分别限制为 1 MiB。
- `release prepare` 在同一父目录下创建 staging 目录。报告写入失败时回滚本次输出，已有 Markdown 报告在 JSON 写入失败时恢复。Bundle 报告也会恢复已有 Markdown。
- MoonHostABI 桥接按已知报告协议核对 schema、退出码、结果和候选 SHA-256，保留上游原始报告。集成测试及 Action 的可选安装器固定使用 MoonHostABI `0.6.1`。发布流程配置 ABI 时使用这个桥接层。
- Action 从所引用的提交构建 CLI，每次调用使用独立报告目录。Linux Action 集成同时验证有意失败的预算和压缩副本。

## 独立贡献与生态分工

| 职责 | 实现来源 |
|---|---|
| WASM 解析、验证、WAT 转换 | `Milky2018/wasm_core` 等生态库 |
| Core ABI 规范化、lock 和兼容性结论 | 可选 MoonHostABI native CLI |
| 优化 pass | 工具链 `moon-wasm-opt` |
| gzip/Brotli 解码、JavaScript/WASM 执行、Worker | Node 标准库与运行时 |
| 发布清单/引用校验、文件捕获与 SHA-256、压缩副本字节比较、消费期望判定、失败聚合及报告 | 本项目 MoonBit 实现 |
| 既有发布规则、精确导入/custom 约束、批次聚合、处理后复检与新目录输出 | 本项目 MoonBit 实现，辅助能力 |
| Action 安装、启动与 GitHub 输出适配 | 本项目薄封装 |

下表记录 2026-11-18 对指定版本的公开文档和命令所做的比较。

| 项目与证据 | 已有能力及复用边界 | 本项目新增检查对象 |
|---|---|---|
| [Wasmoon `2e98651`](https://github.com/Milky2018/wasmoon/blob/2e986517249e056026a84479b48af41a15f5ee88/modules/wasmoon/README.mbt.md) | 解析、验证、转换、WIT 和运行测试。本项目复用其生态解析库。所查 Git 树有自身工作流，无 Action metadata | 声明的发布目录、文件关系和消费契约 |
| [MoonHostABI `b2fcd60`](https://github.com/0717lee/moonhostabi/blob/b2fcd602b68b240b2fcd29a0759b7cd6cfb11c23/docs/consumer-example.md) | ABI lock、兼容性及适配器生成，包含真实 Node 适配器与隔离安装消费测试。本项目委托其 `verify` 静态分析给出 ABI 结论 | 接受构建后的目录与任意声明的 Node ESM 函数，核对压缩副本并运行 WASM/Worker |
| [moonsize `9499de8`](https://github.com/BigSaltyMan/moonsize/blob/9499de8557a3bf529f857e4df01edd2342151632/README.md) | 体积、gzip 测量和预算、函数和包归因、引用图及 CI 报告。仓内也有工具链 setup Action 和 size-check 工作流 | 对磁盘上实际 `.gz`/`.br` 与原件逐字节比较，并检查整个声明文件集合的消费结果 |
| [wasmslim `0.3.1`](https://mooncakes.io/docs/zhangbowen2006/wasmslim@0.3.1) | 公开包文档描述了 debug 段、体积预算、函数变化和可达性分析 | 发布目录中的文件完整性与真实入口执行 |

因此不把“有 Action”“能运行测试”“支持 gzip”“能输出 JSON”单独作为差异。验证用例围绕可复现的问题：源码里有但漏发的 Worker/WASM、仍为上一版的压缩副本、正确进程退出但没有正确消费结果。可先运行 MoonHostABI 和体积分析，再对最终目录运行本工具。

`bundle.parse_manifest` 与 `release.evaluate` 是独立的 MoonBit API，不依赖 CLI、IO 或解析器 AST。两个包在 wasm、wasm-gc、JS、native 均有测试。文件捕获、外部进程及二进制适配在 wasm CLI 执行。
