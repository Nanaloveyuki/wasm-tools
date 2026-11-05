///|
pub async fn cmd_dump(args : Array[String]) -> Int32 raise @cli.CliError {
  let options = @cli.parse_options(args, allow_json=true)
  let instructions = @cli.take_flag(options, "--instructions")
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm dump [OPTIONS] [FILE]\n\nList sections with offsets and sizes.\n  --instructions  Include instruction offsets per function\n  --json          Emit machine-readable JSON\n",
    )
    return 0
  }
  let data = @cli.read_input(options.input)
  let kind = @wasm.detect_kind(data)
  let sections = @wasm.scan_sections(data)
  let text = if options.json {
    @wasm.dump_json(data, sections, kind, instructions)
  } else {
    @wasm.dump_text(data, sections, kind, instructions)
  }
  match options.output {
    None => @cli.write_stdout(text)
    Some(_) => @cli.write_output(options.output, @utf8.encode(text))
  }
  0
}
