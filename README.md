# wasm-tools

使用 MoonBit 实现的 WASM 发布包一致性检查工具，提供本地 `wsm` CLI、清单解析 API 和 GitHub Action。

`bundle check` 面向即将发布的目录：检查声明的 loader、Worker、WASM 和资源文件是否齐全，gzip/Brotli 副本解压后是否与原件一致，以及只复制声明文件后，指定 Node ESM 入口能否加载 WASM、启动 Worker 并返回预期结果。JSON 和 Markdown 报告记录文件 SHA-256、压缩关系与消费结果，失败时返回非零退出码。

已有的 `release check/prepare` 继续提供单产物策略、处理后复检和批次输出。体积与增长预算属于辅助规则，详细归因分析可使用 moonsize 或 wasmslim。

Core ABI 检查由可选的 **MoonHostABI native CLI** 执行。新发布流程不调用本仓库的旧契约比较器。

## 版本与运行

`0.6.0` 是本次源码开发版本，尚未发布到 Mooncakes；已发布的 `0.5.1` 不包含 `bundle` 或 `release` 命令。当前请从源码运行，Action 需引用包含这些命令的仓库提交。

编译器固定在 `.moonbit-toolchain`，本地与 Action 使用同一归档：

```sh
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- "$(cat .moonbit-toolchain)"
export PATH="$HOME/.moon/bin:$PATH"
moon update
moon build --target wasm --release
```

快速体验真实 MoonBit WASM、loader、Worker 和压缩副本（需要 Node.js 20+）：

```sh
bundle_example="$(mktemp -d)"
node scripts/make-bundle-example.mjs "$bundle_example/release"
moonrun _build/wasm/release/build/wasm-tools.wasm -- bundle check "$bundle_example/release/bundle.json" \
  -o "$bundle_example/report.json" --summary "$bundle_example/report.md"
```

示例读取本仓库编译出的 `examples.wasm`，分别在主线程和 Worker 调用 MoonBit 的 `add(20, 22)`，两者都必须得到 `42`。生成器只写新目录；发布清单放在包目录之外。手动替换 `package/calculator.wasm.gz` 为其他版本的副本，即可观察压缩一致性失败。

## 发布包清单

清单显式列出要检查的发布文件，不自动推断 JavaScript 依赖或 npm 打包规则：

```json
{
  "format_version": 1,
  "root": "dist",
  "files": [
    { "path": "loader.mjs" },
    { "path": "worker.mjs" },
    { "path": "calculator.wasm", "kind": "wasm" },
    { "path": "calculator.wasm.gz", "encoding": "gzip", "source": "calculator.wasm" },
    { "path": "calculator.wasm.br", "encoding": "br", "source": "calculator.wasm" }
  ],
  "consumers": [{
    "name": "node-worker",
    "entry": "loader.mjs",
    "requires": ["calculator.wasm", "worker.mjs"],
    "export": "check",
    "args": [20, 22],
    "expected": { "direct": 42, "worker": 42 },
    "timeout_ms": 5000
  }]
}
```

- `root` 相对清单所在目录解析，省略为 `.`，也可指定绝对路径；显式根目录先解析真实路径。其下文件必须使用 `/` 分隔的相对路径，拒绝越界、保留设备名、大小写重复、文件/目录前缀冲突和任一层符号链接。
- `files` 为 1–256 项，捕获总量上限 64 MiB。`kind` 默认 `asset`，`wasm` 调用已有 Core 验证器；`encoding` 默认 `identity`。未知字段、重复 JSON key、错误类型和悬空引用都报配置错误。未声明的文件不复制到消费目录。
- gzip/br 必须引用已声明的 identity 原件，禁止压缩链。文件只读取一次，哈希、解压比对和消费副本都使用捕获的字节。解码由 Node 标准库完成，MoonBit 比较完整字节；解压上限为原件长度加一，拒绝解码器未消费的尾部数据（含填充）。
- `consumers` 可省略，最多 16 项。入口必须是已声明的 identity `.mjs` 文件；`export` 为要调用的函数名，`args` 默认 `[]`，`expected` 必填且可为 `null`。`requires` 可省略，用于校验显式引用；每个用例仍获得全部声明文件。对象键顺序不影响 JSON 比较，数组顺序影响结果。
- 每个用例在新的目录和 Node 子进程运行，默认超时 5000 ms，可设为 100–60000 ms。未捕获全部文件时跳过消费检查，文件失败仍阻止整体通过。异常、结果不符、零退出码但无结果、非 JSON 返回值和超时均失败。日志与结果通道分开；stdout/stderr 各限 1 MiB，报告各保留前 4096 字节，JSON 结果限 1 MiB。

仅检查普通文件及 Core 字节时不依赖 Node；声明压缩副本或消费入口时需要 Node.js 20+，可通过 `--node PATH` 指定。缺少运行时属于 IO 错误。JSON/Markdown 输出不得覆盖清单或声明文件，不接受符号链接目标；后续 JSON 写入失败时恢复已有 Markdown 内容。

消费入口是项目自己的代码，必须自行关闭 Worker 等句柄。子进程仅保留 PATH、系统路径和临时目录环境变量，业务参数通过 `args` 传入。临时目录与清除 `NODE_OPTIONS`/`NODE_PATH` 用于暴露源码目录里的相对依赖漏发；它不限制代码的绝对路径、网络或其他进程访问，也不限制进程内存。首版不验证浏览器环境、不安装 npm 依赖、不检查 tar/zip、npm 包或 OCI 镜像。

## 单产物策略与处理

准备并检查真实 MoonBit 产物：

```sh
moonrun _build/wasm/release/build/wasm-tools.wasm -- release prepare examples/release.json \
  --out-dir dist -o release-report.json --summary release-report.md
```

构建命令也会构建 `examples`。示例移除 `name` 段，保留其他 custom section，对最终文件检查预算和导入规则，成功后生成 `dist/calculator.wasm`。输出目录必须不存在；再次运行时请指定新的目录。

## 发布配置

路径相对配置文件所在目录解析，也接受绝对路径。下例检查已经准备好的发布文件：

```json
{
  "format_version": 1,
  "artifacts": [
    {
      "id": "calculator",
      "input": "build/calculator.wasm",
      "baseline": "previous/calculator.wasm",
      "rules": {
        "max_bytes": 200000,
        "max_growth_bytes": 10000,
        "max_growth_percent": 10,
        "section_budgets": { "code": 150000, "custom:producers": 2000 },
        "allowed_imports": [{ "module": "env", "name": "log" }],
        "required_custom_sections": ["producers"],
        "forbidden_custom_sections": ["name", ".debug_info"]
      }
    }
  ]
}
```

```sh
moonrun _build/wasm/release/build/wasm-tools.wasm -- release check release.json \
  -o report.json --summary report.md
```

配置要求：

- 必填字段为 `format_version`、非空 `artifacts`，以及每个产物的 `id`、`input`、`rules`。
- 未知字段、重复 JSON key、错误类型、负预算、非整数预算和冲突规则会报配置错误。整数上限为 `2147483647`。
- ID 只接受 ASCII 字母、数字、`_`、`-`，忽略大小写后必须唯一，并拒绝 Windows 保留设备名。输出文件名为 `<id>.wasm`。
- 实际值等于阈值时通过。section 字节包含段头，同名 section 合计；未知 Core section 名称报错。`custom:<精确名称>` 按后缀匹配，不存在的 custom section 总量为零，无法判断名称后缀是否拼错。
- 百分比是整数百分比，使用整数交叉乘比较，不先取整。负增长通过；零基线上的正增长不能通过百分比限制。配置增长规则但没有基线会得到失败结果。
- `allowed_imports` 按精确 `(module, name)` 匹配所有种类的导入；省略或 `null` 表示不限制，`[]` 禁止全部导入。名称允许为空，不解释 glob 或正则。
- custom section 规则使用精确名称，包含重复段和空名称；同一名称不能同时 required/forbidden，也不能要求保留又配置移除。

## 准备最终产物

在产物配置中增加处理选项：

```json
"process": {
  "strip_custom_sections": ["name", ".debug_info"],
  "optimize": "-Oz"
}
```

```sh
moonrun _build/wasm/release/build/wasm-tools.wasm -- release prepare release.json \
  --out-dir dist-next -o report.json --summary report.md
```

处理顺序为验证原件、精确移除指定段、可选优化、验证最终字节、运行规则及可选 ABI 检查。`check` 接受最终产物，遇到非空 `process` 会要求使用 `prepare`。

优化调用工具链的 `moon-wasm-opt`，支持 `-O1` 至 `-O4`、`-Os`、`-Oz`，可通过 `--wasm-opt PATH` 指定工具。项目不实现优化 pass，静态验证不证明优化前后行为等价。

增长基线始终是上一版最终发布的 WASM，不执行本次处理。批次内所有产物通过后，才从同一父目录下的 staging 目录发布到新目录；既有目录（包括空目录）和链接均拒绝覆盖。报告写入失败会回滚本次新输出；已有 Markdown 报告在后续 JSON 写入失败时恢复。报告路径不能覆盖配置、输入或基线，也不能放在待发布目录内部。

JSON 报告列出逐项实际值与阈值、原件/最终文件/基线的大小和 SHA-256，以及上游 ABI 原始结果。Markdown 摘要展示大小、section 增减和 ABI 判定；没有发布基线时，变化量相对原件计算，并注明比较来源。

## 复用 MoonHostABI

按固定版本安装原生 CLI，并从已发布产物创建上游 lock：

```sh
moon install 0717lee/moonhostabi/cmd/moonhostabi@0.6.0
moonhostabi lock previous/app.wasm --out previous/app.lock.json
```

为对应产物增加：

```json
"abi": { "baseline": "previous/app.lock.json" }
```

`baseline` 是体积比较用的 WASM；`abi.baseline` 是 MoonHostABI lock JSON，两者独立。配置 ABI 检查后，`release` 调用 `moonhostabi verify ... --format json`，保留上游原始报告并核对已知 schema、退出码、结果和候选 SHA-256。工具不可用、未知或不兼容结果都阻止通过，不回退到自有比较器。

可用 `--moonhostabi PATH` 指定原生 CLI；调用方选择其他安装版本时，桥接层按已知报告协议校验，不检查版本字符串。本仓集成测试和 Action 的可选安装器固定使用 `0.6.0`。ABI 能力范围和生成器可表示性以 [MoonHostABI](https://github.com/0717lee/moonhostabi) 为准。

## GitHub Action

首版 Action 支持 **Linux runner**，需要 Bash、Node.js 20+ 和网络。它固定 MoonBit 工具链，从所引用提交构建 CLI。发布目录和上述清单 `wasm-bundle.json` 准备完成后：

```yaml
- name: Check WASM release bundle
  id: wasm
  uses: ./
  with:
    command: bundle
    config: wasm-bundle.json

- uses: actions/upload-artifact@v4
  if: always()
  with:
    name: wasm-release-report
    path: |
      ${{ steps.wasm.outputs.report-json }}
      ${{ steps.wasm.outputs.summary }}
```

其他仓库将 `uses: ./` 换成 `Nanaloveyuki/wasm-tools@<包含此 Action 的提交 SHA>`，并提供自己的配置。完整的本仓库调用与失败验证见 [.github/workflows/ci.yml](.github/workflows/ci.yml)。

| 输入 | 作用 |
|---|---|
| `config` | 必填，发布包清单或单产物策略配置路径 |
| `command` | `release`（默认，兼容既有调用）或 `bundle` |
| `mode` | `check`（默认）；仅 `release` 支持 `prepare` |
| `out-dir` | prepare 的新目录；省略时在本次独立临时目录内生成 |
| `install-moonhostabi` | `true` 时安装固定的 `0.6.0`；默认 `false` |
| `moonhostabi` | 原生 CLI 名称或路径，默认 `moonhostabi` |
| `wasm-opt` | 可选优化器路径 |

配置含 `abi` 且未提前安装工具时，请设置 `install-moonhostabi: 'true'`。Action 将 Markdown 追加到 Job Summary，输出 `report-json`、`summary`、`status`；仅成功 prepare 输出 `prepared-dir`。规则违规使步骤失败；配置错误无法生成 JSON 时，该路径输出为空，诊断保留在 summary。每次调用使用新报告目录，不复用旧成功结果。

`command: bundle` 使用运行 Action 的 Node 可执行文件执行压缩与消费检查，拒绝 `mode: prepare`、`out-dir` 和 `wasm-opt`。使用单产物处理时保留 `command: release`，设置 `mode: prepare` 和对应策略配置即可。

Action 不自动改写基线、发布 release 或提交 PR 评论；下游根据检查结果决定后续发布步骤。

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

2026-11-18 按下列固定版本核对公开文档与命令面，差异限定为当前实现范围：

| 项目与证据 | 已有能力及复用边界 | 本项目新增检查对象 |
|---|---|---|
| [Wasmoon `2e98651`](https://github.com/Milky2018/wasmoon/blob/2e986517249e056026a84479b48af41a15f5ee88/modules/wasmoon/README.mbt.md) | 解析、验证、转换、WIT 和运行测试；复用其生态解析库。所查 Git 树有自身工作流，无 Action metadata | 声明的发布目录、文件关系和消费契约 |
| [MoonHostABI `b2fcd60`](https://github.com/0717lee/moonhostabi/blob/b2fcd602b68b240b2fcd29a0759b7cd6cfb11c23/docs/consumer-example.md) | ABI lock/兼容性及生成适配器；已有真实 Node 适配器与隔离安装消费测试，`verify` 本身静态分析。本项目委托其 ABI 结论 | 接受构建后的目录与任意声明的 Node ESM 函数，核对压缩副本并运行 WASM/Worker；不重做 ABI 或适配器生成 |
| [moonsize `9499de8`](https://github.com/BigSaltyMan/moonsize/blob/9499de8557a3bf529f857e4df01edd2342151632/README.md) | 体积、gzip 测量/预算、函数/包归因、引用图和 CI 报告；仓内也有工具链 setup Action 和 size-check 工作流 | 对磁盘上实际 `.gz`/`.br` 与原件逐字节比较，并检查整个声明文件集合的消费结果 |
| [wasmslim `0.3.1`](https://mooncakes.io/docs/zhangbowen2006/wasmslim@0.3.1) | debug 段、体积预算、函数变化和可达性分析；以其公开包文档为证据 | 发布目录中的文件完整性与真实入口执行 |

因此不把“有 Action”“能运行测试”“支持 gzip”“能输出 JSON”单独作为差异。验证用例围绕可复现的问题：源码里有但漏发的 Worker/WASM、仍为上一版的压缩副本、正确进程退出但没有正确消费结果。可先运行 MoonHostABI 和体积分析，再对最终目录运行本工具。

`bundle.parse_manifest` 与 `release.evaluate` 是独立的 MoonBit API，不依赖 CLI、IO 或解析器 AST。两个包在 wasm、wasm-gc、JS、native 均有测试；文件捕获、外部进程及二进制适配在 wasm CLI 执行。

## 原有工具与边界

已发布的 `contract snapshot/check`、`contract wit snapshot/check` API 和命令保留原行为，属于旧工作流，不计作本次发布检查产品的独立贡献，也不作为新流程的 ABI 回退。其快照格式与 MoonHostABI lock 不互通。

辅助命令继续保留：`validate`、`print`、`parse`、`dump`、`strip`、`metadata`、`size`、`opt`、`symbolize`、`component wit`。通用 WIT/WAC 操作使用 `moonx moonrockz/wasm-devkit`。

首版 WASM 验证和处理路径限 Core WASM（含上游支持的 MoonBit wasm/wasm-gc），`kind: wasm` 拒绝 Component 二进制；不做递归 Component 策略、运行时资源隔离、行为等价证明或宿主业务逻辑推断。退出码为 `0` 全部通过、`1` 文件/压缩/消费/规则/ABI 检查失败、`2` 用法/配置/IO 错误；IO 错误可能无法生成 JSON，Action 此时提供摘要诊断。

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

发布集成用例覆盖预算边界、重复段、规则负例、真实优化、基线不变、批次失败不发布、报告失败回滚及文件别名保护。设置 `MOONHOSTABI` 或将工具加入 PATH 时，运行真实兼容/破坏性变更与处理后 ABI 检查；未安装时明确跳过 ABI 集成部分，不把它记作已验证。

发布包回归使用真实 zlib 流和 WASM/Worker，覆盖陈旧/损坏/尾随/超限压缩数据、漏发依赖、用例间污染、伪造日志、非 JSON 返回、同步/异步超时、大参数传输及结果上限。

CI 固定 Node 20，包含三平台构建/消费测试、Linux 完整 Action 安装与调用、真实 MoonHostABI 委托，以及有意失败的预算和过期压缩副本。远端执行结果以对应提交的 Actions run 为准。包与 CLI 采用 Apache-2.0 许可；架构与阶段验收记录见 [docs/adr](docs/adr/README.md)。
