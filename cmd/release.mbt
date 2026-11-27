///|
priv struct ReleaseArtifactReport {
  id : String
  input : String
  baseline_path : String?
  before : @release.Facts?
  after : @release.Facts?
  baseline : @release.Facts?
  findings : Array[@release.Finding]
  abi : ReleaseAbiResult?
  error : String?
  exit_code : Int32
}

///|
pub async fn cmd_release(args : Array[String]) -> Int32 raise @cli.CliError {
  if args.is_empty() || args[0] == "--help" || args[0] == "help" {
    @cli.write_stdout(release_help())
    return 0
  }
  let prepare = args[0] == "prepare"
  if args[0] != "check" && !prepare {
    raise @cli.CliError::Usage("unknown release subcommand: " + args[0])
  }
  let options = @cli.parse_options(args[1:].to_owned(), value_options=[
    "--moonhostabi", "--out-dir", "--wasm-opt", "--summary",
  ])
  let executables = @cli.take_value(options, "--moonhostabi")
  let outputs = @cli.take_value(options, "--out-dir")
  let optimizers = @cli.take_value(options, "--wasm-opt")
  let summaries = @cli.take_value(options, "--summary")
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(release_help())
    return 0
  }
  if executables.length() > 1 ||
    outputs.length() > 1 ||
    optimizers.length() > 1 ||
    summaries.length() > 1 {
    raise @cli.CliError::Usage("release options may only be specified once")
  }
  if summaries.get(0) == Some("-") {
    raise @cli.CliError::Usage("--summary requires a file path")
  }
  if prepare && outputs.length() != 1 {
    raise @cli.CliError::Usage(
      "release prepare requires --out-dir NEW_DIRECTORY",
    )
  }
  if !prepare && (!outputs.is_empty() || !optimizers.is_empty()) {
    raise @cli.CliError::Usage(
      "--out-dir and --wasm-opt require release prepare",
    )
  }
  let config_path = match options.input {
    Some(path) if path != "-" => @path.Path(path).resolve().to_string()
    _ => raise @cli.CliError::Usage("release requires a CONFIG file")
  }
  let config_text = @utf8.decode(
    @cli.read_input(Some(config_path)).exact_view(),
  ) catch {
    _ => raise @cli.CliError::Schema("release configuration is not UTF-8")
  }
  let config = @release.parse_config(config_text) catch {
    e => raise @cli.CliError::Schema(e.message())
  }
  for artifact in config.artifacts {
    if !prepare &&
      (
        !artifact.process.strip_custom_sections.is_empty() ||
        artifact.process.optimize is Some(_)
      ) {
      raise @cli.CliError::Usage(
        "release check accepts final artifacts; processing requires release prepare",
      )
    }
  }
  let executable = executables.get(0).unwrap_or("moonhostabi")
  let config_dir = @path.Path(config_path).dirname().to_string()
  release_protect_reports(options.output, config_path, config)
  let summary = summaries.get(0)
  release_protect_reports(summary, config_path, config)
  if options.output is Some(report) && report != "-" && summary is Some(summary) {
    if release_canonical_path(report) == release_canonical_path(summary) {
      raise @cli.CliError::Usage(
        "JSON and Markdown reports require different paths",
      )
    }
  }
  let output_dir = match outputs.get(0) {
    Some(path) => Some(release_new_output(path, [options.output, summary]))
    None => None
  }
  let reports : Array[ReleaseArtifactReport] = []
  let prepared : Array[(String, Bytes)] = []
  for artifact in config.artifacts {
    let (report, data) = check_release_artifact(
      artifact,
      config_dir,
      executable,
      prepare,
      optimizers.get(0),
    ) catch {
      e => (release_error_report(artifact, e), None)
    }
    reports.push(report)
    if data is Some(data) {
      prepared.push((artifact.id + ".wasm", data))
    }
  }
  let code = release_exit_code(reports)
  let previous_summary = match summary {
    Some(path) => {
      let kind = Some(@fs.kind(path)) catch { _ => None }
      if kind == Some(Regular) {
        Some(@cli.read_input(Some(path)))
      } else {
        None
      }
    }
    None => None
  }
  let published = if code == 0 {
    if output_dir is Some(path) {
      release_publish(path, prepared)
    }
    output_dir
  } else {
    None
  }
  let mode = if prepare { "prepare" } else { "check" }
  let report = release_report_json(mode, config_path, reports, published)
  let mut summary_written = false
  errdefer {
    let _ = @async.protect_from_cancel(() => {
      if published is Some(path) {
        let _ = @fs.remove(path, recursive=true) catch { _ => () }
      }
      if summary_written && summary is Some(path) {
        match previous_summary {
          Some(bytes) => {
            let _ = release_write_bytes(Some(path), bytes) catch { _ => () }
          }
          None => {
            let _ = @fs.remove(path) catch { _ => () }
          }
        }
      }
    }) catch {
      _ => ()
    }
  }
  if summary is Some(path) {
    release_write_report(Some(path), release_markdown(mode, reports, published))
    summary_written = true
  }
  release_write_report(options.output, report.stringify() + "\n")
  code
}

///|
fn release_help() -> String {
  "Usage: wsm release <check|prepare> CONFIG [OPTIONS]\n\n" +
  "  check                  Check already-final Core Wasm artifacts\n" +
  "  prepare                Process and recheck artifacts before publication\n" +
  "  --out-dir DIR          New directory for prepared artifacts (required for prepare)\n" +
  "  --wasm-opt PATH        Override the optimizer for prepare\n" +
  "  --moonhostabi PATH     MoonHostABI native CLI (default: moonhostabi)\n" +
  "  --summary FILE         Write a Markdown release report\n" +
  "  -o FILE                Write the JSON report instead of stdout\n"
}

///|
async fn release_new_output(
  path : String,
  reports : Array[String?],
) -> String raise @cli.CliError {
  let output = @path.Path(path).resolve().to_string()
  let occupied = Some(@fs.kind(output, follow_symlink=false)) catch {
    _ => None
  }
  if occupied is Some(_) {
    raise @cli.CliError::Usage(
      "release output directory must not already exist: " + output,
    )
  }
  let parent = @path.Path(output).dirname().to_string()
  let parent = @fs.realpath(parent) catch {
    e => raise @cli.CliError::Io("release output parent: " + e.to_string())
  }
  let output = release_path(parent, @path.Path(output).basename().to_owned())
  for report in reports {
    if report is Some(report) && report != "-" {
      let report = release_canonical_path(report)
      if report == output || report.has_prefix(output + @path.sep.to_string()) {
        raise @cli.CliError::Usage(
          "write reports outside the prepared output directory",
        )
      }
    }
  }
  output
}

///|
async fn release_publish(
  output : String,
  artifacts : Array[(String, Bytes)],
) -> Unit raise @cli.CliError {
  let seed = @fs.tmpdir(prefix="wsm-release-stage-") catch {
    e => raise @cli.CliError::Io(e.to_string())
  }
  defer {
    let _ = @fs.remove(seed) catch { _ => () }
  }
  let parent = @path.Path(output).dirname().to_string()
  let stage = release_path(parent, "." + @path.Path(seed).basename().to_owned())
  @fs.mkdir(stage) catch {
    e => raise @cli.CliError::Io("cannot stage release: " + e.to_string())
  }
  defer {
    let _ = @fs.remove(stage, recursive=true) catch { _ => () }
  }
  for (name, bytes) in artifacts {
    @fs.write_binary(release_path(stage, name), bytes, create_mode=CreateNew) catch {
      e => raise @cli.CliError::Io("cannot stage release: " + e.to_string())
    }
  }
  @fs.rename(stage, output, replace=false) catch {
    e => raise @cli.CliError::Io("cannot publish release: " + e.to_string())
  }
}

///|
async fn release_canonical_path(path : String) -> String noraise {
  let absolute = @path.Path(path).resolve().to_string()
  @fs.realpath(absolute) catch {
    _ => {
      let parent = @path.Path(absolute).dirname().to_string()
      if parent == absolute {
        absolute
      } else {
        release_path(
          release_canonical_path(parent),
          @path.Path(absolute).basename().to_owned(),
        )
      }
    }
  }
}

///|
async fn release_write_report(
  output : String?,
  text : String,
) -> Unit raise @cli.CliError {
  release_write_bytes(output, @utf8.encode(text))
}

///|
async fn release_write_bytes(
  output : String?,
  data : Bytes,
) -> Unit raise @cli.CliError {
  guard output is Some(output) && output != "-" else {
    @cli.write_output(None, data)
    return
  }
  let target = @path.Path(output).resolve().to_string()
  let parent = @path.Path(target).dirname().to_string()
  let seed = @fs.tmpdir(prefix="wsm-release-report-") catch {
    e => raise @cli.CliError::Io(e.to_string())
  }
  defer {
    let _ = @fs.remove(seed) catch { _ => () }
  }
  let stage = release_path(parent, "." + @path.Path(seed).basename().to_owned())
  @fs.mkdir(stage) catch {
    e => raise @cli.CliError::Io(e.to_string())
  }
  defer {
    let _ = @fs.remove(stage, recursive=true) catch { _ => () }
  }
  let staged_file = release_path(stage, "report")
  @fs.write_binary(staged_file, data) catch {
    e => raise @cli.CliError::Io(e.to_string())
  }
  @fs.rename(staged_file, target, replace=true) catch {
    e => raise @cli.CliError::Io(e.to_string())
  }
}

///|
async fn release_protect_reports(
  output : String?,
  config_path : String,
  config : @release.Config,
) -> Unit raise @cli.CliError {
  guard output is Some(output) && output != "-" else { return }
  let target = release_canonical_path(output)
  let directory = @path.Path(config_path).dirname().to_string()
  let protected_paths = [config_path]
  for artifact in config.artifacts {
    protected_paths.push(release_path(directory, artifact.input))
    if artifact.baseline is Some(file) {
      protected_paths.push(release_path(directory, file))
    }
    if artifact.abi is Some(check) {
      protected_paths.push(release_path(directory, check.baseline))
    }
  }
  for path in protected_paths {
    if target == release_canonical_path(path) {
      raise @cli.CliError::Usage(
        "report output must not overwrite an input or baseline",
      )
    }
  }
}

///|
fn release_path(directory : String, file : String) -> String {
  let path = @path.Path(file)
  if path.is_absolute() {
    path.normalize().to_string()
  } else {
    @path.Path(directory).join(path).normalize().to_string()
  }
}

///|
async fn check_release_artifact(
  artifact : @release.Artifact,
  directory : String,
  executable : String,
  prepare : Bool,
  optimizer : String?,
) -> (ReleaseArtifactReport, Bytes?) raise @cli.CliError {
  let input = release_path(directory, artifact.input)
  let original = @cli.read_input(Some(input))
  let before = @wasm.release_facts(original)
  let mut data = original
  if prepare {
    if !artifact.process.strip_custom_sections.is_empty() {
      data = @wasm.strip_custom_sections(data, @wasm.scan_sections(data), name => {
        artifact.process.strip_custom_sections.contains(name)
      })
    }
    if artifact.process.optimize is Some(level) {
      let optimizer = @wasm.Optimizer::new(@wasm.find_optimizer(optimizer))
      data = @wasm.run_optimizer(optimizer, data, level, [])
    }
  }
  let facts = if prepare { @wasm.release_facts(data) } else { before }
  let baseline = match artifact.baseline {
    Some(file) =>
      Some(
        @wasm.release_facts(
          @cli.read_input(Some(release_path(directory, file))),
        ),
      )
    None => None
  }
  let findings = @release.evaluate(artifact.rules, facts, baseline)
  let abi = match artifact.abi {
    Some(check) =>
      Some(
        release_verify_abi(
          data,
          release_path(directory, check.baseline),
          executable,
        ),
      )
    None => None
  }
  let abi_failed = match abi {
    Some(result) => !result.passed
    None => false
  }
  let failed = !findings.is_empty() || abi_failed
  let report : ReleaseArtifactReport = {
    id: artifact.id,
    input: artifact.input,
    baseline_path: artifact.baseline,
    before: Some(before),
    after: Some(facts),
    baseline,
    findings,
    abi,
    error: None,
    exit_code: if failed {
      1
    } else {
      0
    },
  }
  (report, Some(data))
}

///|
fn release_error_report(
  artifact : @release.Artifact,
  error : @cli.CliError,
) -> ReleaseArtifactReport {
  {
    id: artifact.id,
    input: artifact.input,
    baseline_path: artifact.baseline,
    before: None,
    after: None,
    baseline: None,
    findings: [],
    abi: None,
    error: Some(error.message()),
    exit_code: error.exit_code(),
  }
}

///|
fn release_exit_code(reports : Array[ReleaseArtifactReport]) -> Int32 {
  let mut code = 0
  for report in reports {
    if report.exit_code > code {
      code = report.exit_code
    }
  }
  code
}

///|
fn release_status(code : Int32) -> String {
  match code {
    0 => "passed"
    1 => "failed"
    _ => "error"
  }
}

///|
fn release_optional_string(value : String?) -> Json {
  match value {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

///|
fn release_facts_json(facts : @release.Facts?) -> Json {
  match facts {
    None => Json::null()
    Some(facts) =>
      Json::object({
        "bytes": Json::number(facts.bytes.to_double()),
        "sha256": Json::string(facts.sha256),
        "sections": Json::array(
          facts.sections.map(section => {
            Json::object({
              "name": Json::string(section.name),
              "bytes": Json::number(section.bytes.to_double()),
            })
          }),
        ),
        "imports": Json::array(
          facts.imports.map(entry => {
            Json::object({
              "module": Json::string(entry.import_module),
              "name": Json::string(entry.name),
            })
          }),
        ),
        "custom_sections": Json::array(
          facts.custom_sections.map(name => Json::string(name)),
        ),
      })
  }
}

///|
fn release_artifact_json(report : ReleaseArtifactReport) -> Json {
  let abi = match report.abi {
    None => Json::null()
    Some(abi) =>
      Json::object({
        "tool": Json::string("MoonHostABI"),
        "passed": Json::boolean(abi.passed),
        "exit_code": Json::number(abi.exit_code.to_double()),
        "report": abi.report.unwrap_or(Json::null()),
        "error": release_optional_string(abi.error),
      })
  }
  Json::object({
    "id": Json::string(report.id),
    "input": Json::string(report.input),
    "baseline_path": release_optional_string(report.baseline_path),
    "status": Json::string(release_status(report.exit_code)),
    "before": release_facts_json(report.before),
    "after": release_facts_json(report.after),
    "baseline": release_facts_json(report.baseline),
    "findings": Json::array(
      report.findings.map(finding => {
        Json::object({
          "rule": Json::string(finding.rule),
          "message": Json::string(finding.message),
          "actual": finding.actual,
          "limit": finding.limit,
        })
      }),
    ),
    "abi": abi,
    "error": release_optional_string(report.error),
  })
}

///|
fn release_report_json(
  mode : String,
  config : String,
  reports : Array[ReleaseArtifactReport],
  output_dir : String?,
) -> Json {
  Json::object({
    "format_version": Json::number(1.0),
    "mode": Json::string(mode),
    "config": Json::string(config),
    "status": Json::string(release_status(release_exit_code(reports))),
    "output_dir": release_optional_string(output_dir),
    "artifacts": Json::array(reports.map(release_artifact_json)),
  })
}
