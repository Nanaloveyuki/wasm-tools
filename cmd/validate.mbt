///|
pub async fn cmd_validate(args : Array[String]) -> Int32 raise @cli.CliError {
  let options = @cli.parse_options(args)
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm validate [OPTIONS] [FILE]\n\nParse and validate a module or component from FILE or stdin.\n",
    )
    return 0
  }
  let data = @cli.read_input(options.input)
  match @wasm.detect_kind(data) {
    @wasm.CoreModule => {
      @wasm.validate_core(data)
      @cli.write_stdout(
        "valid core module (" + data.length().to_string() + " bytes)\n",
      )
    }
    @wasm.Component => {
      @wasm.validate_component(data)
      @cli.write_stdout(
        "valid component (" + data.length().to_string() + " bytes)\n",
      )
    }
  }
  0
}
