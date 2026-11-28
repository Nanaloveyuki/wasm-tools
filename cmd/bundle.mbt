///|
priv struct BundleCapture {
  observations : Array[@bundle.FileObservation]
  data : Map[String, Bytes]
  findings : Array[@bundle.Finding]
}

///|
priv enum BundleFiles {
  DirectoryFiles(String, Map[String, Unit]?)
  ArchiveFiles(Map[String, Bytes])
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
    "--summary", "--node", "--npm-archive",
  ])
  let summaries = @cli.take_value(options, "--summary")
  let nodes = @cli.take_value(options, "--node")
  let archives = @cli.take_value(options, "--npm-archive")
  let strict_files = @cli.take_flag(options, "--strict-files")
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(bundle_help())
    return 0
  }
  if summaries.length() > 1 || nodes.length() > 1 || archives.length() > 1 {
    raise @cli.CliError::Usage("bundle options may only be specified once")
  }
  if summaries.get(0) == Some("-") {
    raise @cli.CliError::Usage("--summary requires a file path")
  }
  let manifest_input = match options.input {
    Some(path) if path != "-" => @path.Path(path).resolve().to_string()
    _ => raise @cli.CliError::Usage("bundle check requires a MANIFEST file")
  }
  let manifest_bytes = @cli.read_input(Some(manifest_input))
  let text = @utf8.decode(manifest_bytes.exact_view()) catch {
    _ => raise @cli.CliError::Schema("bundle manifest is not UTF-8")
  }
  let manifest = @bundle.parse_manifest(text) catch {
    e => raise @cli.CliError::Schema(e.message())
  }
  let node = nodes.get(0).unwrap_or("node")
  let node_path = @path.Path(node)
  let node = if node_path.basename() != node[:] {
    node_path.resolve().to_string()
  } else {
    node
  }
  let manifest_path = release_canonical_path(manifest_input)
  let summary = summaries.get(0)
  let reports = [options.output, summary]
  let (root, archive, capture) = match archives.get(0) {
    Some(path) => {
      if path.is_empty() || path == "-" {
        raise @cli.CliError::Usage("--npm-archive requires a file path")
      }
      let archive = release_canonical_path(path)
      bundle_protect_reports(reports, [manifest_path, archive], None)
      let capture = bundle_capture_archive(
        archive, manifest, strict_files, node,
      )
      ("package/", Some(archive), capture)
    }
    None => {
      let root = bundle_directory_root(manifest_input, manifest.root)
      let protected_paths = [manifest_path, root]
      for file in manifest.files {
        protected_paths.push(release_path(root, file.path))
      }
      bundle_protect_reports(
        reports,
        protected_paths,
        if strict_files {
          Some(root)
        } else {
          None
        },
      )
      let inventory = if strict_files {
        Some(bundle_inventory(root))
      } else {
        None
      }
      let capture = bundle_capture(DirectoryFiles(root, inventory), manifest)
      (root, None, capture)
    }
  }
  let findings = capture.findings
  let compressions = bundle_check_compressions(
    manifest,
    capture.data,
    findings,
    node,
  )
  let consumers = bundle_check_consumers(manifest, capture.data, findings, node)
  let report = bundle_report_json(
    manifest_path,
    root,
    archive,
    capture.observations,
    findings,
    compressions,
    consumers,
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
  "  --strict-files         Reject files outside the manifest\n" +
  "  --npm-archive FILE     Check an npm tarball in place of the manifest root\n" +
  "  --node PATH            Node.js 20+ for tarballs, encoded files and consumers\n" +
  "  --summary FILE         Write a Markdown bundle report\n" +
  "  -o FILE                Write JSON instead of stdout\n"
}

///|
async fn bundle_directory_root(
  manifest_path : String,
  configured_root : String,
) -> String raise @cli.CliError {
  let manifest = @path.Path(manifest_path)
  let root = @fs.realpath(
    release_path(manifest.dirname().to_string(), configured_root),
  ) catch {
    e => raise @cli.CliError::Io("bundle root: " + e.to_string())
  }
  let kind = @fs.kind(root) catch {
    e => raise @cli.CliError::Io("bundle root: " + e.to_string())
  }
  if kind != Directory {
    raise @cli.CliError::Io("bundle root is not a directory")
  }
  root
}

///|
async fn bundle_protect_reports(
  reports : Array[String?],
  protected_paths : Array[String],
  strict_root : String?,
) -> Unit raise @cli.CliError {
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
      if strict_root is Some(root) && bundle_within_directory(target, root) {
        raise @cli.CliError::Usage(
          "--strict-files requires report outputs outside the bundle root",
        )
      }
    }
  }
}

///|
fn bundle_within_directory(path : String, root : String) -> Bool {
  for current = path {
    if current == root {
      return true
    }
    let parent = @path.Path(current).dirname().to_string()
    if parent == current {
      return false
    }
    continue parent
  }
}

///|
async fn bundle_capture_archive(
  archive : String,
  manifest : @bundle.Manifest,
  strict_files : Bool,
  node : String,
) -> BundleCapture raise @cli.CliError {
  let members = bundle_read_npm_archive(archive, node) catch {
    @cli.CliError::Invalid(message) =>
      return {
        observations: [],
        data: Map([]),
        findings: [
          {
            code: "archive_invalid",
            path: archive,
            related_path: None,
            message,
          },
        ],
      }
    error => raise error
  }
  let capture = bundle_capture(ArchiveFiles(members), manifest)
  if strict_files {
    bundle_report_undeclared(
      members.keys().to_array(),
      manifest,
      capture.findings,
    )
  }
  capture
}

///|
async fn bundle_capture(
  source : BundleFiles,
  manifest : @bundle.Manifest,
) -> BundleCapture noraise {
  let observations : Array[@bundle.FileObservation] = []
  let data : Map[String, Bytes] = Map([])
  let findings : Array[@bundle.Finding] = []
  let mut total = 0
  for file in manifest.files {
    let bytes : Result[Bytes, BundleReadError] = Ok(
      match source {
        DirectoryFiles(root, inventory) =>
          bundle_read_file(root, file.path, 67108864 - total, inventory)
        ArchiveFiles(members) =>
          match members.get(file.path) {
            Some(bytes) => bytes
            None =>
              raise BundleReadError(
                "file_missing",
                "declared file is missing from the npm archive: " + file.path,
              )
          }
      },
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
  if source is DirectoryFiles(_, Some(inventory)) {
    bundle_report_undeclared(inventory.keys().to_array(), manifest, findings)
  }
  { observations, data, findings, }
}

///|
async fn bundle_read_file(
  root : String,
  file : String,
  remaining : Int32,
  inventory : Map[String, Unit]?,
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
  if inventory is Some(files) && !files.contains(file) {
    raise BundleReadError(
      "file_missing",
      "declared file is missing with its exact path spelling: " + file,
    )
  }
  let size = @fs.file_size(path) catch {
    e => raise BundleReadError("file_read", e.to_string())
  }
  if size > remaining.to_int64() {
    raise BundleReadError("capture_limit", "bundle capture exceeds 64 MiB")
  }
  let bytes = @fs.read_binary(path) catch {
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
