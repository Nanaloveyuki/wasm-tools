///|
pub async fn cmd_contract(args : Array[String]) -> Int32 raise @cli.CliError {
  if args.is_empty() {
    raise @cli.CliError::Usage(
      "contract requires a subcommand: snapshot or check",
    )
  }
  let subcommand = args[0]
  let rest = args[1:].to_owned()
  match subcommand {
    "snapshot" => contract_snapshot(rest)
    "check" => contract_check(rest)
    "wit" => contract_wit(rest)
    "-h" | "--help" | "help" => {
      @cli.write_stdout(contract_help())
      0
    }
    _ =>
      raise @cli.CliError::Usage("unknown contract subcommand: " + subcommand)
  }
}

///|
async fn contract_wit(args : Array[String]) -> Int32 raise @cli.CliError {
  if args.is_empty() {
    raise @cli.CliError::Usage(
      "contract wit requires a subcommand: snapshot or check",
    )
  }
  let subcommand = args[0]
  let rest = args[1:].to_owned()
  match subcommand {
    "snapshot" => contract_wit_snapshot(rest)
    "check" => contract_wit_check(rest)
    "-h" | "--help" | "help" => {
      @cli.write_stdout(contract_wit_help())
      0
    }
    _ =>
      raise @cli.CliError::Usage(
        "unknown contract wit subcommand: " + subcommand,
      )
  }
}

///|
async fn contract_wit_snapshot(
  args : Array[String],
) -> Int32 raise @cli.CliError {
  let options = @cli.parse_options(args, value_options=["--world"])
  let worlds = @cli.take_value(options, "--world")
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm contract wit snapshot --world NAME [FILE]\n\nWrite a deterministic WIT world contract snapshot as JSON.\n",
    )
    return 0
  }
  if worlds.length() != 1 {
    raise @cli.CliError::Usage(
      "contract wit snapshot requires exactly one --world",
    )
  }
  let data = @cli.read_input(options.input)
  let snapshot = @wasm.wit_world_snapshot(data, worlds[0])
  @cli.write_output(
    options.output,
    @utf8.encode(@contract.wit_snapshot_json(snapshot) + "\n"),
  )
  0
}

///|
async fn contract_wit_check(args : Array[String]) -> Int32 raise @cli.CliError {
  let options = @cli.parse_options(args, allow_json=true, value_options=[
    "--baseline", "--world",
  ])
  let baselines = @cli.take_value(options, "--baseline")
  let worlds = @cli.take_value(options, "--world")
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(contract_wit_help())
    return 0
  }
  if baselines.length() != 1 || baselines[0] == "-" {
    raise @cli.CliError::Usage(
      "contract wit check requires one file-valued --baseline",
    )
  }
  if worlds.length() != 1 {
    raise @cli.CliError::Usage(
      "contract wit check requires exactly one --world",
    )
  }
  let candidate_path = match options.input {
    Some(path) => path
    None =>
      raise @cli.CliError::Usage(
        "contract wit check requires a candidate WIT FILE",
      )
  }
  let baseline_bytes = @cli.read_input(Some(baselines[0]))
  let baseline_text = @utf8.decode(baseline_bytes.exact_view()) catch {
    _ => raise @cli.CliError::Schema("baseline WIT snapshot is not valid UTF-8")
  }
  let baseline = @contract.parse_wit_snapshot(baseline_text) catch {
    error => raise @cli.CliError::Schema(error.message())
  }
  let candidate = @wasm.wit_world_snapshot(
    @cli.read_input(Some(candidate_path)),
    worlds[0],
  )
  let report = @contract.compare_wit_snapshots(baseline, candidate)
  let output = if options.json {
    @contract.wit_report_json(report) + "\n"
  } else {
    @contract.wit_report_text(report)
  }
  @cli.write_output(options.output, @utf8.encode(output))
  if report.status == @contract.Compatible {
    0
  } else {
    1
  }
}

///|
async fn contract_snapshot(args : Array[String]) -> Int32 raise @cli.CliError {
  let options = @cli.parse_options(args)
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm contract snapshot [FILE]\n\nWrite a deterministic Core WASM contract snapshot as JSON.\n",
    )
    return 0
  }
  let data = @cli.read_input(options.input)
  let snapshot = @wasm.contract_snapshot(data)
  let output = @contract.snapshot_json(snapshot) + "\n"
  @cli.write_output(options.output, @utf8.encode(output))
  0
}

///|
async fn contract_check(args : Array[String]) -> Int32 raise @cli.CliError {
  let options = @cli.parse_options(args, allow_json=true, value_options=[
    "--baseline", "--direction",
  ])
  let baseline_paths = @cli.take_value(options, "--baseline")
  let directions = @cli.take_value(options, "--direction")
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm contract check --baseline SNAPSHOT FILE [OPTIONS]\n\nCompare the module's imports and exports with a snapshot.\n  --baseline FILE   Snapshot produced by contract snapshot\n  --direction MODE provided, required, or both (default: both)\n  --json            Emit a machine-readable report\n  -o FILE           Write the report to FILE\n",
    )
    return 0
  }
  if baseline_paths.length() != 1 {
    raise @cli.CliError::Usage(
      "contract check requires exactly one --baseline snapshot",
    )
  }
  if baseline_paths[0] == "-" {
    raise @cli.CliError::Usage(
      "--baseline must be a file when candidate input uses stdin",
    )
  }
  let direction = parse_direction(directions)
  let candidate_path = match options.input {
    Some(path) => path
    None =>
      raise @cli.CliError::Usage("contract check requires a candidate FILE")
  }
  let baseline_bytes = @cli.read_input(Some(baseline_paths[0]))
  let baseline_text = @utf8.decode(baseline_bytes.exact_view()) catch {
    _ => raise @cli.CliError::Schema("baseline snapshot is not valid UTF-8")
  }
  let baseline = @contract.parse_snapshot(baseline_text) catch {
    error => raise @cli.CliError::Schema(error.message())
  }
  let candidate_bytes = @cli.read_input(Some(candidate_path))
  let candidate = @wasm.contract_snapshot(candidate_bytes)
  let report = @contract.compare_snapshots(baseline, candidate, direction)
  let output = if options.json {
    @contract.report_json(report) + "\n"
  } else {
    @contract.report_text(report)
  }
  @cli.write_output(options.output, @utf8.encode(output))
  if report_has_failure(report) {
    1
  } else {
    0
  }
}

///|
fn parse_direction(
  values : Array[String],
) -> @contract.Direction raise @cli.CliError {
  if values.length() > 1 {
    raise @cli.CliError::Usage("--direction may only be specified once")
  }
  if values.is_empty() {
    return @contract.Both
  }
  match values[0] {
    "provided" => @contract.Provided
    "required" => @contract.Required
    "both" => @contract.Both
    _ =>
      raise @cli.CliError::Usage(
        "--direction must be provided, required, or both",
      )
  }
}

///|
fn report_has_failure(report : @contract.Report) -> Bool {
  for direction_report in report.reports {
    if direction_report.status != @contract.Compatible {
      return true
    }
  }
  false
}

///|
fn contract_help() -> String {
  "Usage: wsm contract <snapshot|check|wit> [OPTIONS]\n\n" +
  "  snapshot [FILE]  Write a deterministic Core WASM contract snapshot\n" +
  "  check            Compare imports and exports with a baseline snapshot\n" +
  "  wit              Snapshot and check an explicitly selected WIT world\n"
}

///|
fn contract_wit_help() -> String {
  "Usage: wsm contract wit <snapshot|check> [OPTIONS]\n\n" +
  "  snapshot --world NAME [FILE]  Write a WIT world snapshot\n" +
  "  check --world NAME --baseline SNAPSHOT FILE  Check WIT compatibility\n" +
  "  --json                         Emit a machine-readable report\n" +
  "  -o FILE                        Write output to FILE\n"
}
