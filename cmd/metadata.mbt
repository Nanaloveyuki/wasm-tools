///|
pub async fn cmd_metadata(args : Array[String]) -> Int raise @cli.CliError {
  let options = @cli.parse_options(args, allow_json=true)
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm metadata [OPTIONS] [FILE]\n\nShow the name and producers custom sections.\n",
    )
    return 0
  }
  let data = @cli.read_input(options.input)
  let kind = @wasm.detect_kind(data)
  let text = @wasm.metadata_text(data, kind, options.json)
  match options.output {
    None => @cli.write_stdout(text)
    Some(_) => @cli.write_output(options.output, @utf8.encode(text))
  }
  0
}
