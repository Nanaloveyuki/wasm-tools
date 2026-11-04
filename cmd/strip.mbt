///|
pub async fn cmd_strip(args : Array[String]) -> Int raise @cli.CliError {
  let options = @cli.parse_options(args, value_options=["--keep"])
  let keep = @cli.take_value(options, "--keep")
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm strip [OPTIONS] [FILE]\n\nRemove custom sections from a module or component.\n  --keep NAME     Keep the named custom section (repeatable)\n",
    )
    return 0
  }
  let data = @cli.read_input(options.input)
  let sections = @wasm.scan_sections(data)
  let binary = @wasm.strip_custom_sections(
    data,
    sections,
    fn(name) {
      !keep.contains(name)
    },
  )
  @cli.write_output(options.output, binary)
  0
}
