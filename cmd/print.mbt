///|
pub async fn cmd_print(args : Array[String]) -> Int32 raise @cli.CliError {
  let options = @cli.parse_options(args)
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm print [OPTIONS] [FILE]\n\nPrint a module or component as WAT.\n",
    )
    return 0
  }
  let data = @cli.read_input(options.input)
  let text = match @wasm.detect_kind(data) {
    @wasm.CoreModule => @wasm.core_to_wat(data)
    @wasm.Component => @wasm.component_to_wat(data)
  }
  match options.output {
    None => @cli.write_stdout(text)
    Some(_) => @cli.write_output(options.output, @utf8.encode(text))
  }
  0
}
