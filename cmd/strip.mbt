///|
pub async fn cmd_strip(args : Array[String]) -> Int raise @cli.CliError {
  let options = @cli.parse_options(args, value_options=["--keep"])
  let keep = @cli.take_value(options, "--keep")
  let all = @cli.take_flag(options, "--all")
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm strip [OPTIONS] [FILE]\n\nRemove custom sections.\n  --all           Remove every custom section (default)\n  --keep NAME     Keep the named custom section (repeatable)\n",
    )
    return 0
  }
  let data = @cli.read_input(options.input)
  let sections = @wasm.scan_sections(data)
  let drop = fn(name : String) -> Bool {
    if !all && keep.is_empty() {
      // 默认删除所有 custom section，与 wasm-tools strip 一致
      true
    } else {
      let mut matched = false
      for kept in keep {
        if kept == name {
          matched = true
        }
      }
      !matched
    }
  }
  let binary = @wasm.strip_custom_sections(data, sections, drop)
  @cli.write_output(options.output, binary)
  0
}
