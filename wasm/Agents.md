# wasm 包约束

- 本包是唯一允许出现 `Milky2018/wasm_core`、`Milky2018/wasm_component`、
  `moonrockz/wit` 类型的层。`cmd` 只见本包导出的 `Bytes`/`String`/`InputKind`。
- `raw.mbt`/`custom.mbt` 只做字节级扫描，不解析语义；所有越界必须报
  `@cli.CliError::Invalid`，不允许 panic 或静默截断。
- `core.mbt`/`component.mbt` 各自只依赖一条上游链路。core 用 `wasm_core`，
  component 的 WAT 打印用 `moonrockz/wit/decompiler`；两条链路不互相转换。
- 组件二进制在 `dump`/`metadata` 中显式拒绝（见 `kind.mbt::reject_component`），
  不要用 core 的 section id 表猜组件 section。
