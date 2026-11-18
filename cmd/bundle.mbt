///|
priv struct BundleCapture {
  observations : Array[@bundle.FileObservation]
  data : Map[String, Bytes]
  findings : Array[@bundle.Finding]
}

///|
priv suberror BundleReadError {
  BundleReadError(String, String)
}

///|
pub async fn cmd_bundle(args : Array[String]) -> Int32 raise @cli.CliError {
  if args.is_empty() || args[0] == "--help" || args[0] == "help" {
    @cli.write_stdout(bundle_help())
    return 0
  }
  if args[0] != "check" {
    raise @cli.CliError::Usage("unknown bundle subcommand: " + args[0])
  }
  let options = @cli.parse_options(args[1:].to_owned(), value_options=[
    "--summary", "--node",
  ])
  let summaries = @cli.take_value(options, "--summary")
  let nodes = @cli.take_value(options, "--node")
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(bundle_help())
    return 0
  }
  if summaries.length() > 1 || nodes.length() > 1 {
    raise @cli.CliError::Usage("bundle options may only be specified once")
  }
  if summaries.get(0) == Some("-") {
    raise @cli.CliError::Usage("--summary requires a file path")
  }
  let manifest_path = match options.input {
    Some(path) if path != "-" => @path.Path(path).resolve().to_string()
    _ => raise @cli.CliError::Usage("bundle check requires a MANIFEST file")
  }
  let text = @utf8.decode(@cli.read_input(Some(manifest_path)).exact_view()) catch {
    _ => raise @cli.CliError::Schema("bundle manifest is not UTF-8")
  }
  let manifest = @bundle.parse_manifest(text) catch {
    e => raise @cli.CliError::Schema(e.message())
  }
  let directory = @path.Path(manifest_path).dirname().to_string()
  let root = @fs.realpath(release_path(directory, manifest.root)) catch {
    e => raise @cli.CliError::Io("bundle root: " + e.to_string())
  }
  let root_kind = @fs.kind(root) catch {
    e => raise @cli.CliError::Io("bundle root: " + e.to_string())
  }
  if root_kind != Directory {
    raise @cli.CliError::Io("bundle root is not a directory")
  }
  let summary = summaries.get(0)
  bundle_protect_reports(
    [options.output, summary],
    manifest_path,
    root,
    manifest,
  )
  let capture = bundle_capture(root, manifest)
  let findings = capture.findings
  let compressions = bundle_check_compressions(
    manifest,
    capture.data,
    findings,
    nodes.get(0).unwrap_or("node"),
  )
  for consumer in manifest.consumers {
    findings.push({
      code: "consumer_unsupported",
      path: consumer.entry,
      related_path: None,
      message: "consumer checks are not implemented yet: " + consumer.name,
    })
  }
  let report = bundle_report_json(
    manifest_path,
    root,
    capture.observations,
    findings,
    compressions,
    [],
  )
  bundle_write_reports(options.output, summary, report, bundle_markdown(report))
  if findings.is_empty() {
    0
  } else {
    1
  }
}

///|
fn bundle_help() -> String {
  "Usage: wsm bundle check MANIFEST [OPTIONS]\n\n" +
  "  --node PATH            Node.js 20+ for encoded files and consumers\n" +
  "  --summary FILE         Write a Markdown bundle report\n" +
  "  -o FILE                Write JSON instead of stdout\n"
}

///|
async fn bundle_protect_reports(
  reports : Array[String?],
  manifest_path : String,
  root : String,
  manifest : @bundle.Manifest,
) -> Unit raise @cli.CliError {
  let protected_paths = [manifest_path, root]
  for file in manifest.files {
    protected_paths.push(release_path(root, file.path))
  }
  let targets : Array[String] = []
  for report in reports {
    if report is Some(report) && report != "-" {
      let kind = Some(@fs.kind(report, follow_symlink=false)) catch {
        _ => None
      }
      if kind == Some(SymLink) {
        raise @cli.CliError::Usage("report output must not be a symlink")
      }
      let target = release_canonical_path(report)
      if targets.contains(target) {
        raise @cli.CliError::Usage(
          "JSON and Markdown reports require different paths",
        )
      }
      targets.push(target)
      for path in protected_paths {
        if target == release_canonical_path(path) {
          raise @cli.CliError::Usage(
            "report output must not overwrite a bundle input",
          )
        }
      }
    }
  }
}

///|
async fn bundle_capture(
  root : String,
  manifest : @bundle.Manifest,
) -> BundleCapture noraise {
  let observations : Array[@bundle.FileObservation] = []
  let data : Map[String, Bytes] = Map([])
  let findings : Array[@bundle.Finding] = []
  let mut total = 0
  for file in manifest.files {
    let bytes : Result[Bytes, BundleReadError] = Ok(
      bundle_read_file(root, file.path, 67108864 - total),
    ) catch {
      e => Err(e)
    }
    match bytes {
      Err(BundleReadError(code, message)) => {
        observations.push({
          path: file.path,
          bytes: None,
          sha256: None,
          error: Some(message),
        })
        findings.push({ code, path: file.path, related_path: None, message, })
      }
      Ok(bytes) => {
        total += bytes.length()
        data.set(file.path, bytes)
        let mut error : String? = None
        if file.kind is Wasm {
          @wasm.validate_core(bytes) catch {
            e => {
              error = Some(e.message())
              findings.push({
                code: "wasm_invalid",
                path: file.path,
                related_path: None,
                message: e.message(),
              })
            }
          }
        }
        observations.push({
          path: file.path,
          bytes: Some(bytes.length()),
          sha256: Some(@crypto.bytes_to_hex_string(@crypto.sha256(bytes))),
          error,
        })
      }
    }
  }
  { observations, data, findings, }
}

///|
async fn bundle_read_file(
  root : String,
  file : String,
  remaining : Int32,
) -> Bytes raise BundleReadError {
  let segments = file.split("/").to_array()
  let mut path = root
  for index, segment in segments {
    path = release_path(path, segment.to_owned())
    let kind = @fs.kind(path, follow_symlink=false) catch {
      e =>
        raise BundleReadError(
          "file_missing",
          "cannot inspect " + file + ": " + e.to_string(),
        )
    }
    if kind == SymLink {
      raise BundleReadError("file_symlink", "symlink in declared path: " + file)
    }
    if index + 1 == segments.length() {
      if kind != Regular {
        raise BundleReadError(
          "file_not_regular",
          "declared path is not a regular file: " + file,
        )
      }
    } else if kind != Directory {
      raise BundleReadError(
        "file_not_directory",
        "parent is not a directory: " + file,
      )
    }
  }
  let size = @fs.file_size(path) catch {
    e => raise BundleReadError("file_read", e.to_string())
  }
  if size > remaining.to_int64() {
    raise BundleReadError("capture_limit", "bundle capture exceeds 64 MiB")
  }
  let bytes = @fs.read_file(path).binary() catch {
    e => raise BundleReadError("file_read", e.to_string())
  }
  if bytes.length() > remaining {
    raise BundleReadError("capture_limit", "bundle capture exceeds 64 MiB")
  }
  bytes
}

///|
async fn bundle_write_reports(
  output : String?,
  summary : String?,
  report : Json,
  markdown : String,
) -> Unit raise @cli.CliError {
  let previous = match summary {
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
  let mut written = false
  errdefer {
    let _ = @async.protect_from_cancel(() => {
      if written && summary is Some(path) {
        match previous {
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
    release_write_report(Some(path), markdown)
    written = true
  }
  release_write_report(output, report.stringify() + "\n")
}
