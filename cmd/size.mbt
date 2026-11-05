///|
pub async fn cmd_size(args : Array[String]) -> Int raise @cli.CliError {
  let options = @cli.parse_options(args, allow_json=true, value_options=["--top"])
  let top_values = @cli.take_value(options, "--top")
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm size [OPTIONS] [FILE]\n\nReport section and function sizes.\n  --top N   Show only the N largest functions (default 10)\n  --json    Emit machine-readable JSON\n",
    )
    return 0
  }
  let mut top = 10
  if top_values.length() > 0 {
    top = try @str.parse_int(top_values[0]) catch {
      _ => { raise @cli.CliError::Usage("--top expects an integer") }
    }
    if top < 0 {
      raise @cli.CliError::Usage("--top must not be negative")
    }
  }
  let data = @cli.read_input(options.input)
  let file = options.input.unwrap_or("<stdin>")
  let report = @wasm.size_report(data, file)
  let text = if options.json {
    @wasm.size_json(report)
  } else {
    @wasm.size_text(report, top)
  }
  match options.output {
    None => @cli.write_stdout(text)
    Some(_) => @cli.write_output(options.output, @utf8.encode(text))
  }
  0
}
