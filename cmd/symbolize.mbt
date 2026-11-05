///|
pub async fn cmd_symbolize(args : Array[String]) -> Int raise @cli.CliError {
  let options = @cli.parse_options(args, allow_json=true)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm symbolize [OPTIONS] [FILE] ADDRESS\n\nMap a wasm stack address to a function name using the name section.\nAccepts `wasm-function[16]:0x947` or a hex absolute offset.\n  --json    Emit machine-readable JSON\n",
    )
    return 0
  }
  if options.extra.length() == 0 {
    raise @cli.CliError::Usage("missing ADDRESS")
  }
  let address = options.extra[0]
  @cli.reject_unknown_extra(@cli.without_first(options.extra))
  let data = @cli.read_input(options.input)
  let symbol = @wasm.symbolize(data, address)
  let text = if options.json {
    @wasm.symbolize_json(symbol)
  } else {
    @wasm.symbolize_text(symbol)
  }
  @cli.write_stdout(text)
  0
}
