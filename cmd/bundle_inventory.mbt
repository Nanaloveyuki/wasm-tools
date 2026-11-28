///|
async fn bundle_inventory(
  root : String,
) -> Map[String, Unit] raise @cli.CliError {
  let files : Map[String, Unit] = Map([])
  let directories = [""]
  while directories.pop() is Some(relative) {
    let directory = release_path(root, relative)
    let reader = @fs.opendir(directory) catch {
      error =>
        raise @cli.CliError::Io(
          "cannot list bundle directory: " + error.to_string(),
        )
    }
    defer reader.close()
    for ;; {
      let entry = reader.next() catch {
        error =>
          raise @cli.CliError::Io(
            "cannot read bundle directory: " + error.to_string(),
          )
      }
      guard entry is Some(entry) else { break }
      let path = if relative.is_empty() {
        entry.name
      } else {
        relative + "/" + entry.name
      }
      if entry.is_dir {
        directories.push(path)
      } else {
        files[path] = ()
      }
    }
  }
  files
}

///|
fn bundle_report_undeclared(
  paths : Array[String],
  manifest : @bundle.Manifest,
  findings : Array[@bundle.Finding],
) -> Unit {
  let declared : Map[String, Unit] = Map([])
  for file in manifest.files {
    declared[file.path] = ()
  }
  paths.sort()
  for path in paths {
    if !declared.contains(path) {
      findings.push({
        code: "file_undeclared",
        path,
        related_path: None,
        message: "file is not declared in the bundle manifest",
      })
    }
  }
}
