# wasm-tools

使用 MoonBit 实现的 WASM 发布产物检查与处理工具，提供本地 `wsm` CLI、可复用的规则 API 和 GitHub Action。

同一份发布配置可以检查多个产物的体积、增长量、section 预算、宿主导入和 custom section；也可以先清理或优化，再对最终文件执行相同检查。结果包含 JSON、Markdown 和处理前后的 SHA-256，检查失败会阻止产物发布。

Core ABI 检查由可选的 **MoonHostABI native CLI** 执行。新发布流程不调用本仓库的旧契约比较器。

## 版本与运行

`0.6.0` 是本次源码开发版本，尚未发布到 Mooncakes；已发布的 `0.5.1` 不包含 `release` 命令。当前请从源码运行，Action 需引用包含 `action.yml` 的仓库提交。

编译器固定在 `.moonbit-toolchain`，本地与 Action 使用同一归档：

```sh
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- "$(cat .moonbit-toolchain)"
export PATH="$HOME/.moon/bin:$PATH"
moon build --target wasm --release
```

快速体验真实 MoonBit 产物：

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

首版 Action 支持 **Linux runner**，需要 Bash、Node.js 20+ 和网络。它固定 MoonBit 工具链，从所引用提交构建 CLI；规则与处理逻辑均由 MoonBit 执行。应用构建完成后，本仓库可这样调用：

```yaml
- name: Prepare WASM release
  id: wasm
  uses: ./
  with:
    config: examples/release.json
    mode: prepare

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
| `config` | 必填，发布配置路径 |
| `mode` | `check`（默认）或 `prepare` |
| `out-dir` | prepare 的新目录；省略时在本次独立临时目录内生成 |
| `install-moonhostabi` | `true` 时安装固定的 `0.6.0`；默认 `false` |
| `moonhostabi` | 原生 CLI 名称或路径，默认 `moonhostabi` |
| `wasm-opt` | 可选优化器路径 |

配置含 `abi` 且未提前安装工具时，请设置 `install-moonhostabi: 'true'`。Action 将 Markdown 追加到 Job Summary，输出 `report-json`、`summary`、`status`；仅成功 prepare 输出 `prepared-dir`。规则违规使步骤失败；配置错误无法生成 JSON 时，该路径输出为空，诊断保留在 summary。每次调用使用新报告目录，不复用旧成功结果。

Action 不自动改写基线、发布 release 或提交 PR 评论；下游根据检查结果决定后续发布步骤。

## 独立贡献与生态分工

| 职责 | 实现来源 |
|---|---|
| WASM 解析、验证、WAT 转换 | `Milky2018/wasm_core` 等生态库 |
| Core ABI 规范化、lock 和兼容性结论 | 可选 MoonHostABI native CLI |
| 优化 pass | 工具链 `moon-wasm-opt` |
| 发布配置、预算与增长规则、精确导入/custom 约束、批次聚合、处理后复检、发布与报告 | 本项目 MoonBit 实现 |
| Action 安装、启动与 GitHub 输出适配 | 本项目薄封装 |

对照 `wasmoon@0.19.0` 及默认分支 `40379a3`，其已有验证、转换、WIT、运行测试和完善的自身 CI；该提交未提供 Action metadata 或 `workflow_call` 入口。项目差异集中在用户发布产物的配置化规则及处理流程，不能仅以“有 CI”“能批量运行”“输出 JSON”作为独立贡献。[固定版本命令](https://github.com/Milky2018/wasmoon/blob/40379a3b7bde338ebb1dbbbb7822a7e3a92daab8/modules/wasmoon/cmd/wasmoon-tools/main.mbt)、[工作流](https://github.com/Milky2018/wasmoon/blob/40379a3b7bde338ebb1dbbbb7822a7e3a92daab8/.github/workflows/check.yml)。

`release` 纯规则包不依赖 CLI、IO、解析器 AST 或 MoonHostABI，可由 MoonBit 程序构造 `Facts` 后调用 `evaluate`。该包在 wasm、wasm-gc、JS、native 均有测试；二进制适配和 CLI 当前仍为 wasm target。

## 原有工具与边界

已发布的 `contract snapshot/check`、`contract wit snapshot/check` API 和命令保留原行为，属于旧工作流，不计作本次发布检查产品的独立贡献，也不作为新流程的 ABI 回退。其快照格式与 MoonHostABI lock 不互通。

辅助命令继续保留：`validate`、`print`、`parse`、`dump`、`strip`、`metadata`、`size`、`opt`、`symbolize`、`component wit`。通用 WIT/WAC 操作使用 `moonx moonrockz/wasm-devkit`。

首版发布路径限 Core WASM（含上游支持的 MoonBit wasm/wasm-gc），拒绝 Component 二进制；不做递归 Component 策略、运行时资源隔离、行为等价证明或宿主业务逻辑推断。退出码为 `0` 全部通过、`1` 产物/规则/ABI 检查失败、`2` 用法/配置/IO 错误；每个产物均报告，批次错误优先于普通检查失败。

## 开发与验证

```sh
moon check --target all --deny-warn
moon test --target all --deny-warn
moon fmt
moon info
moon build --target wasm
./tests/smoke.sh
MOONHOSTABI=moonhostabi python3 tests/release-check.py
WSM_CLI_WASM="$PWD/_build/wasm/debug/build/wasm-tools.wasm" node tests/action-runner.mjs
```

发布集成用例覆盖预算边界、重复段、规则负例、真实优化、基线不变、批次失败不发布、报告失败回滚及文件别名保护。设置 `MOONHOSTABI` 或将工具加入 PATH 时，运行真实兼容/破坏性变更与处理后 ABI 检查；未安装时明确跳过 ABI 集成部分，不把它记作已验证。

CI 配置包含三平台构建/测试、Linux Action 安装与调用、真实 MoonHostABI 委托和拒绝过预算产物。远端执行结果以对应提交的 Actions run 为准。包与 CLI 采用 Apache-2.0 许可；架构与阶段验收记录见 [docs/adr](docs/adr/README.md)。
