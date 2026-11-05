///|
pub async fn cmd_component(args : Array[String]) -> Int32 raise @cli.CliError {
  if args.is_empty() {
    raise @cli.CliError::Usage("component requires a subcommand: wit")
  }
  let subcommand = args[0]
  let rest = args[1:].to_owned()
  match subcommand {
    "wit" => component_wit(rest)
    "-h" | "--help" | "help" => {
      @cli.write_stdout(
        "Usage: wsm component wit [OPTIONS] [FILE]\n\nExtract the WIT package embedded in a component.\n",
      )
      0
    }
    _ =>
      raise @cli.CliError::Usage("unknown component subcommand: " + subcommand)
  }
}

///|
async fn component_wit(args : Array[String]) -> Int32 raise @cli.CliError {
  let options = @cli.parse_options(args)
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm component wit [OPTIONS] [FILE]\n\nExtract the WIT package embedded in a component.\n",
    )
    return 0
  }
  let data = @cli.read_input(options.input)
  let text = @wasm.component_to_wit(data)
  match options.output {
    None => @cli.write_stdout(text)
    Some(_) => @cli.write_output(options.output, @utf8.encode(text))
  }
  0
}
