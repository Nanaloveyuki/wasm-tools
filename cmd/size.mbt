///|
pub async fn cmd_size(args : Array[String]) -> Int32 raise @cli.CliError {
  let options = @cli.parse_options(args, allow_json=true, value_options=[
    "--top", "--diff", "--budget",
  ])
  let top_values = @cli.take_value(options, "--top")
  let diff_values = @cli.take_value(options, "--diff")
  let budget_values = @cli.take_value(options, "--budget")
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm size [OPTIONS] [FILE]\n\nReport section and function sizes.\n  --top N        Show only the N largest functions (default 10, 0 = all)\n  --diff FILE    Compare function sizes against a baseline build\n  --budget SIZE  Fail when the total exceeds SIZE (B/KB/MB)\n  --json         Emit machine-readable JSON\n",
    )
    return 0
  }
  let top = parse_top(top_values)
  let budget = parse_budget(budget_values)
  let data = @cli.read_input(options.input)
  let file = options.input.unwrap_or("<stdin>")
  let report = @wasm.size_report(data, file)
  if diff_values.length() > 0 {
    let baseline_data = @cli.read_input(Some(diff_values[0]))
    let baseline = @wasm.size_report(baseline_data, diff_values[0])
    let diff = @wasm.size_diff(report, baseline)
    let text = if options.json {
      @wasm.diff_json(diff)
    } else {
      @wasm.diff_text(diff, top)
    }
    @cli.write_output(options.output, @utf8.encode(text))
    return 0
  }
  let text = if options.json {
    @wasm.size_json(report)
  } else {
    @wasm.size_text(report, top)
  }
  match options.output {
    None => @cli.write_stdout(text)
    Some(_) => @cli.write_output(options.output, @utf8.encode(text))
  }
  match budget {
    Some(limit) =>
      if report.total > limit {
        let message = @cli.TOOL_NAME +
          ": size " +
          report.total.to_string() +
          " B exceeds budget " +
          limit.to_string() +
          " B\n"
        @cli.write_stderr(message) catch {
          _ => ()
        }
        return 1
      }
    None => ()
  }
  0
}

///|
fn parse_top(values : Array[String]) -> Int32 raise @cli.CliError {
  if values.length() == 0 {
    return 10
  }
  let top = @str.parse_int(values[0]) catch {
    _ => raise @cli.CliError::Usage("--top expects an integer")
  }
  if top < 0 {
    raise @cli.CliError::Usage("--top must not be negative")
  }
  top
}

///|
/// 只接受 `123`、`123B`、`12KB`、`3MB`；1024 进制，避免和磁盘厂商的 1000 进制混淆。
fn parse_budget(values : Array[String]) -> Int32? raise @cli.CliError {
  if values.length() == 0 {
    return None
  }
  let text = values[0].trim().to_owned().to_upper()
  let mut number_part = text
  let mut multiplier = 1
  if text.has_suffix("KB") {
    number_part = text
      .get_view(start=0, end=text.length() - 2)
      .unwrap_or("")
      .to_owned()
    multiplier = 1024
  } else if text.has_suffix("MB") {
    number_part = text
      .get_view(start=0, end=text.length() - 2)
      .unwrap_or("")
      .to_owned()
    multiplier = 1024 * 1024
  } else if text.has_suffix("B") {
    number_part = text
      .get_view(start=0, end=text.length() - 1)
      .unwrap_or("")
      .to_owned()
  }
  let base = @str.parse_int(number_part) catch {
    _ => raise @cli.CliError::Usage("--budget expects a size like 200KB")
  }
  if base < 0 {
    raise @cli.CliError::Usage("--budget must not be negative")
  }
  Some(base * multiplier)
}
