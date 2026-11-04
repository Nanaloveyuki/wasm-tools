///|
/// core module 适配层。所有 `wasm_core` 类型都止步于本文件。
pub fn validate_core(data : Bytes) -> Unit raise @cli.CliError {
  let parsed = try @core_parser.parse_module(data) catch {
    e => raise @cli.CliError::Invalid("parse: " + e.to_string())
  }
  try @core_validator.validate_module(parsed) catch {
    e => raise @cli.CliError::Invalid(@core_validator.format_validation_error(e))
  }
}

///|
pub fn core_to_wat(data : Bytes) -> String raise @cli.CliError {
  let parsed = try @core_parser.parse_module(data) catch {
    e => raise @cli.CliError::Invalid("parse: " + e.to_string())
  }
  try @core_wat.render(parsed) catch {
    e => raise @cli.CliError::Invalid("print: " + e.to_string())
  }
}

///|
pub fn wat_to_core(text : String) -> Bytes raise @cli.CliError {
  let parsed = try @core_wat.parse(text) catch {
    e => raise @cli.CliError::Invalid(@core_wat.format_wat_error(e, text))
  }
  let bytes : Array[Byte] = @core_encoder.encode(parsed).map(fn(i) {
    i.to_byte()
  })
  Bytes::from_array(bytes)
}
