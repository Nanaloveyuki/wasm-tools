///|
pub async fn cmd_opt(args : Array[String]) -> Int raise @cli.CliError {
  let options = @cli.parse_options(args, value_options=["--wasm-opt", "--passes"])
  let wasm_opt = @cli.take_value(options, "--wasm-opt")
  let passes = @cli.take_value(options, "--passes")
  let (level, remaining) = pick_level(options)
  let explicit = @cli.take_value(options, "--level")
  @cli.reject_unknown_extra(remaining)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm opt [OPTIONS] [FILE]\n\nOptimize a core module with moon-wasm-opt (binaryen).\n  -O1..-O4, -Os, -Oz  Optimization level (default -O2)\n  --passes P1,P2      Additional binaryen passes\n  --wasm-opt PATH     Use a specific moon-wasm-opt binary\n  -o FILE             Write the result to FILE\n",
    )
    return 0
  }
  let selected = if explicit.length() > 0 { explicit[0] } else { level }
  let data = @cli.read_input(options.input)
  match @wasm.detect_kind(data) {
    @wasm.Component =>
      raise @cli.CliError::Unsupported("opt: component binaries need the component pipeline; use `component wit` or `print` first")
    @wasm.CoreModule => ()
  }
  let explicit_path = if wasm_opt.length() > 0 { Some(wasm_opt[0]) } else { None }
  let path = @wasm.find_optimizer(explicit_path)
  let extra : Array[String] = []
  for entry in passes {
    for part in entry.split(",") {
      let trimmed = part.trim().to_owned()
      if !trimmed.is_empty() {
        extra.push(trimmed)
      }
    }
  }
  let optimizer = @wasm.Optimizer::new(path)
  let result = @wasm.run_optimizer(optimizer, data, selected, extra)
  @cli.write_output(options.output, result)
  0
}

///|
/// `-O2` 这类短选项由 `parse_options` 放进 extra；这里挑第一个并转成 binaryen 的写法。
fn pick_level(options : @cli.Options) -> (String, Array[String]) {
  let levels = ["-O1", "-O2", "-O3", "-O4", "-Os", "-Oz"]
  let found : Array[String] = []
  let rest : Array[String] = []
  for arg in options.extra {
    let mut matched = false
    for level in levels {
      if arg == level {
        found.push(level)
        matched = true
      }
    }
    if !matched {
      rest.push(arg)
    }
  }
  let level = if found.length() > 0 { found[0] } else { "-O2" }
  (level, rest)
}
