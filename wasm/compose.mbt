///|
/// WAC 组合。解析与组装交给 `mizchi/mwac`，这里只负责依赖定位与结果校验。
///
/// mwac 只认 `<base>/deps/<ns>/<name>.wasm`；`--dep` 通过临时目录里的符号
/// 替换实现，因此不需要 fork 上游的解析器。
pub(all) struct ComposeOptions {
  /// .wac 文本所在目录，决定默认的 deps 路径
  mut base : String
  /// 包名（`ns:name`）到 wasm 路径的覆盖
  mut deps : Map[String, String]
  mut dce : Bool
  mut best_effort : Bool
}

///|
pub fn ComposeOptions::new(base : String) -> ComposeOptions {
  { base, deps: Map([]), dce: false, best_effort: false }
}

///|
/// 从 WAC 文本中取出所有 `new ns:name {...}` 的包名。
pub fn compose_packages(source : String) -> Array[String] raise @cli.CliError {
  let document = match @composer.parse_wac(source) {
    Ok(document) => document
    Err(error) => raise @cli.CliError::Invalid("wac parse: " + error.to_string())
  }
  let names : Array[String] = []
  for statement in document.stmts {
    match statement {
      @composer.Let(_, @composer.New(new_expr)) => {
        if !names.contains(new_expr.pkg) {
          names.push(new_expr.pkg)
        }
      }
      _ => ()
    }
  }
  names
}

///|
pub async fn compose(options : ComposeOptions, source : String) -> Bytes raise @cli.CliError {
  let packages = compose_packages(source)
  // 先确认每个包都能定位，否则 mwac 只会报 "failed to read component"
  for name in packages {
    match options.deps.get(name) {
      Some(path) =>
        if !(try @fs.exists(path) catch { _ => false }) {
          raise @cli.CliError::Io("--dep " + name + ": no such file: " + path)
        }
      None => {
        let path = default_dep_path(options.base, name)
        if !(try @fs.exists(path) catch { _ => false }) {
          raise @cli.CliError::Io(
            "cannot find " +
            name +
            " at " +
            path +
            "; pass --dep " +
            name +
            "=PATH",
          )
        }
      }
    }
  }
  if options.deps.is_empty() {
    let bytes = match @composer.compose_wac_source(source, options.base, best_effort=options.best_effort, dce=options.dce) {
      Ok(bytes) => bytes
      Err(message) => raise @cli.CliError::Invalid("compose: " + message)
    }
    verify_component(bytes)
    return bytes
  }
  // 有覆盖时必须阻止 mwac 读到原路径，否则 --dep 会静默失效
  let staging = try @fs.tmpdir(prefix="wsm-compose-") catch {
    e => raise @cli.CliError::Io("cannot create a temporary directory: " + e.to_string())
  }
  defer {
    let _ = try @fs.rmdir(staging, recursive=true) catch {
      _ => ()
    }
  }
  for name, path in options.deps {
    let target_dir = staging + "/deps/" + dep_namespace(name)
    let created = try @fs.mkdir(target_dir, recursive=true, allow_exist=true) catch {
      e => raise @cli.CliError::Io("cannot prepare " + target_dir + ": " + e.to_string())
    }
    ignore(created)
    let bytes = try @fs.read_file(path).binary() catch {
      e => raise @cli.CliError::Io(path + ": " + e.to_string())
    }
    let target = target_dir + "/" + dep_name(name) + ".wasm"
    try @fs.write_file(target, bytes) catch {
      e => raise @cli.CliError::Io("cannot stage " + target + ": " + e.to_string())
    }
  }
  // 未覆盖的包仍从原目录解析：把原 deps 里缺的部分补进 staging
  for name in packages {
    if options.deps.contains(name) {
      continue
    }
    let source_path = default_dep_path(options.base, name)
    let target_dir = staging + "/deps/" + dep_namespace(name)
    let created = try @fs.mkdir(target_dir, recursive=true, allow_exist=true) catch {
      e => raise @cli.CliError::Io("cannot prepare " + target_dir + ": " + e.to_string())
    }
    ignore(created)
    let bytes = try @fs.read_file(source_path).binary() catch {
      e => raise @cli.CliError::Io(source_path + ": " + e.to_string())
    }
    try @fs.write_file(target_dir + "/" + dep_name(name) + ".wasm", bytes) catch {
      e => raise @cli.CliError::Io("cannot stage " + source_path + ": " + e.to_string())
    }
  }
  let bytes = match @composer.compose_wac_source(source, staging, best_effort=options.best_effort, dce=options.dce) {
    Ok(bytes) => bytes
    Err(message) => raise @cli.CliError::Invalid("compose: " + message)
  }
  verify_component(bytes)
  bytes
}

///|
/// mwac 的默认约定：`<base>/deps/<ns>/<name>.wasm`
fn default_dep_path(base : String, pkg : String) -> String {
  base + "/deps/" + dep_namespace(pkg) + "/" + dep_name(pkg) + ".wasm"
}

///|
/// `ns:name` → `ns`
fn dep_namespace(pkg : String) -> String {
  let parts : Array[String] = []
  for part in pkg.split(":") {
    parts.push(part.to_owned())
  }
  if parts.length() >= 1 {
    parts[0]
  } else {
    pkg
  }
}

///|
/// `ns:name` → `name`
fn dep_name(pkg : String) -> String {
  let parts : Array[String] = []
  for part in pkg.split(":") {
    parts.push(part.to_owned())
  }
  if parts.length() >= 2 {
    parts[1]
  } else {
    pkg
  }
}

///|
fn verify_component(bytes : Bytes) -> Unit raise @cli.CliError {
  validate_component(bytes)
}
