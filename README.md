# wasm-tools

检查即将发布的 WASM 文件、目录和 npm 包。可在本地运行 CLI，也可在 GitHub Actions 中把检查结果作为发布门禁。

| 命令 | 用途 |
| --- | --- |
| `bundle check` | 检查目录或 npm `.tgz`，验证文件清单、WASM、gzip/Brotli 副本和 Node 消费结果 |
| `release check` | 检查最终 WASM 的体积与增长预算、导入、custom section 及可选 Core ABI |
| `release prepare` | 移除指定 custom section、可选优化，检查通过后把产物写入新目录 |

## 运行 CLI

安装 MoonBit 后，用 `moonx` 运行 0.7.0。下文的 `wsm` 代表同一条命令。

```sh
moonx Nanaloveyuki/wasm-tools@0.7.0 --help
alias wsm='moonx Nanaloveyuki/wasm-tools@0.7.0'
```

npm 归档、gzip/Brotli 副本及消费检查需要 Node.js 20 或更新版本。可用 `--node PATH` 指定可执行文件。

## 检查发布包

把清单保存为 `wasm-bundle.json`。下面的例子会检查 `dist` 中的 loader、Worker、WASM 和压缩副本。消费用例会调用 `loader.mjs` 的 `check(20, 22)`，并比较它返回的 JSON 值。

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
    "expected": { "direct": 42, "worker": 42 }
  }]
}
```

```sh
wsm bundle check wasm-bundle.json -o report.json --summary report.md
wsm bundle check wasm-bundle.json --strict-files
wsm bundle check wasm-bundle.json --npm-archive ./example-1.0.0.tgz
```

- `root` 相对于清单所在目录，默认是 `.`，也接受绝对路径。`files[].path` 是以 `/` 分隔的相对路径。每包最多声明 256 个文件，声明文件合计上限 64 MiB。声明路径须使用普通文件，且不含符号链接。
- `kind` 默认是 `asset`。`kind: "wasm"` 检查 Core WASM。压缩文件的 `encoding` 是 `gzip` 或 `br`，`source` 指向清单里的未压缩原件。
- `--strict-files` 按完整路径和大小写检查缺失及额外文件。隐藏文件计入清单，空目录忽略。严格检查目录时，将报告放在根目录之外。放在根目录中的清单本身也算一个文件。
- 用 `npm pack` 生成 `.tgz`，再用 `--npm-archive` 检查实际打包文件。清单路径对应归档的 `package/` 内部，`root` 只用于目录检查。严格检查时须声明包内的 `package.json`、README 和许可证等随包文件。压缩归档和解压后的 tar 各限 72 MiB。
- 可配置最多 16 个 `consumers`。入口必须是已声明的未压缩 `.mjs` 文件。`args` 默认是 `[]`，`expected` 必填且可为 `null`，`requires` 可选。每个用例获得全部声明文件，默认超时 5000 ms，可通过 `timeout_ms` 设为 100–60000 ms。消费代码拥有普通 Node 进程的文件和网络权限，须自行关闭 Worker 等句柄。
- JSON 比较忽略对象键顺序，保留数组顺序，并比较精确的十进制值。`args` 进入 JavaScript 后遵循 `Number` 精度。报告记录文件大小、SHA-256、压缩比对与消费结果。消费结果限 1 MiB，报告分别保留 stdout 和 stderr 的前 4096 字节。

## 检查和准备 WASM 产物

把策略保存为 `release.json`。路径以配置文件所在目录为起点，也可以用绝对路径。每项产物填写 `id`、`input` 和 `rules`。

```json
{
  "format_version": 1,
  "artifacts": [{
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
  }]
}
```

```sh
wsm release check release.json -o report.json --summary report.md
```

- 增长预算使用 `baseline` 指向的上一版最终 WASM。预算等于阈值时通过。段预算包含段头，同名段合计。
- `allowed_imports` 按 `module` 和 `name` 精确匹配。省略或填写 `null` 表示允许任意导入，`[]` 禁止全部导入。custom section 按名称精确匹配。
- 需要处理产物时，给对应的产物项加入 `"process": { "strip_custom_sections": ["name", ".debug_info"], "optimize": "-Oz" }`，再用 `wsm release prepare release.json --out-dir dist-next -o report.json`。所有产物通过后才会生成新目录，文件名为 `<id>.wasm`。可用 `--wasm-opt PATH` 指定优化器，支持 `-O1` 至 `-O4`、`-Os` 和 `-Oz`。

### 可选 Core ABI 检查

安装 MoonHostABI 并用上一版发布产物生成 lock。

```sh
moon install 0717lee/moonhostabi/cmd/moonhostabi@0.6.1
moonhostabi lock previous/calculator.wasm --out previous/calculator.lock.json
```

给对应的产物项加入 `"abi": { "baseline": "previous/calculator.lock.json" }`。增长预算仍使用产物项中的 `baseline`。可以用 `--moonhostabi PATH` 指定原生 CLI，或在 Action 中设置 `install-moonhostabi: 'true'`。

## GitHub Action

在 Linux runner 上配置 Node.js 20 或更新版本，构建或打包项目后运行检查。

```yaml
- name: Check WASM release bundle
  id: wasm
  uses: Nanaloveyuki/wasm-tools@v0.7.0
  with:
    command: bundle
    config: wasm-bundle.json
    strict-files: 'true'

- uses: actions/upload-artifact@v4
  if: always()
  with:
    name: wasm-release-report
    path: |
      ${{ steps.wasm.outputs.report-json }}
      ${{ steps.wasm.outputs.summary }}
```

| 输入 | 用途 |
| --- | --- |
| `config` | 必填，清单或策略配置路径 |
| `command` | `release`（默认）或 `bundle` |
| `mode` | `check`（默认）或 `prepare`，后者仅用于 `release` |
| `out-dir` | `release prepare` 的新目录，省略时使用临时目录 |
| `strict-files` | `true` 时严格匹配文件清单，用于 `bundle`，默认 `false` |
| `npm-archive` | 用于 `bundle` 的 npm `.tgz` 路径，相对路径以工作区为起点 |
| `install-moonhostabi` | `true` 时安装 MoonHostABI 0.6.1，默认 `false` |
| `moonhostabi` | MoonHostABI 命令名或路径，默认 `moonhostabi` |
| `wasm-opt` | `release prepare` 使用的可选优化器路径 |

Action 输出 `report-json`、`summary` 和 `status`，并将 Markdown 加入 Job Summary。成功运行 `release prepare` 时还会输出 `prepared-dir`。

## 其他功能

- 用 `validate`、`print`、`parse` 验证二进制并转换 WAT，用 `dump`、`metadata`、`strip` 检查或移除自定义段。
- 用 `size` 查看大小、对比基线或设置预算，用 `opt` 调用优化器，用 `symbolize` 将栈地址映射到函数名。
- 用 `component wit` 提取内嵌 WIT。可用 `contract snapshot/check` 比较 Core 契约，用 `contract wit snapshot/check` 比较 WIT 契约。WIT 格式 1 基线会得到 `unknown`，请用原始 WIT 生成新基线。
- 在 MoonBit 项目中可调用发布清单解析和策略规则 API。参见 [Bundle API](bundle/README.mbt.md) 与 [Release API](release/README.mbt.md)。

检查退出码为 `0` 通过，`1` 未通过，`2` 用法、配置或 IO 错误。Bundle 和 Release 的 JSON 报告默认写入 stdout，可用 `-o` 写入文件，用 `--summary` 生成 Markdown。请将报告路径与输入文件分开。

[贡献指南](CONTRIBUTING.md) · [许可证](LICENSE)
