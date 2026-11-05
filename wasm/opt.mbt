///|
/// `moon-wasm-opt` 的调用桥。只负责找二进制、传参、回收输出，不实现优化本身。
pub(all) struct Optimizer {
  mut path : String
}

///|
pub fn Optimizer::new(path : String) -> Optimizer {
  { path, }
}

///|
/// 候选顺序：显式路径 → `$MOON_HOME/bin` → `PATH`。Windows 需要 `.exe` 后缀，
/// 因此每个目录都试两种拼写，并用 `--version` 探测是否真的可执行。
pub async fn find_optimizer(explicit : String?) -> String raise @cli.CliError {
  // 显式路径是权威的：用户指错了就应该报错，而不是悄悄用另一个 binaryen
  match explicit {
    Some(path) => {
      let ok = probe_optimizer(path) catch { _ => false }
      if ok {
        return path
      }
      raise @cli.CliError::Io(
        "--wasm-opt " + path + " is not a working moon-wasm-opt binary",
      )
    }
    None => ()
  }
  let candidates : Array[String] = []
  match @env.get_env_var("MOON_HOME") {
    Some(home) => {
      candidates.push(home + "/bin/moon-wasm-opt")
      candidates.push(home + "/bin/moon-wasm-opt.exe")
    }
    None => ()
  }
  candidates.push("moon-wasm-opt")
  candidates.push("moon-wasm-opt.exe")
  for candidate in candidates {
    let ok = probe_optimizer(candidate) catch { _ => false }
    if ok {
      return candidate
    }
  }
  raise @cli.CliError::Unsupported(
    "moon-wasm-opt not found; install the MoonBit toolchain or pass --wasm-opt PATH",
  )
}

///|
async fn probe_optimizer(path : String) -> Bool {
  let result = @process.collect_output(path, ["--version"]) catch {
    _ => return false
  }
  result.0 == 0
}

///|
pub async fn run_optimizer(
  optimizer : Optimizer,
  data : Bytes,
  level : String,
  passes : Array[String],
) -> Bytes raise @cli.CliError {
  let dir = @fs.tmpdir(prefix="wsm-opt-") catch {
    e =>
      raise @cli.CliError::Io(
        "cannot create a temporary directory: " + e.to_string(),
      )
  }
  let input = dir + "/input.wasm"
  let output = dir + "/output.wasm"
  // 临时文件必须清理，否则 `moonx` 反复调用会堆满临时目录
  defer {
    let _ = @fs.remove(output) catch { _ => () }
    let _ = @fs.remove(input) catch { _ => () }
    let _ = @fs.rmdir(dir) catch { _ => () }
  }
  @fs.write_file(input, data) catch {
    e =>
      raise @cli.CliError::Io(
        "cannot write the temporary input: " + e.to_string(),
      )
  }
  let args : Array[String] = ["--all-features", level]
  for pass in passes {
    args.push("--" + pass)
  }
  args.push(input)
  args.push("-o")
  args.push(output)
  let (code, _, stderr) = @process.collect_output(optimizer.path, args) catch {
    e =>
      raise @cli.CliError::Unsupported(
        "cannot run " + optimizer.path + ": " + e.to_string(),
      )
  }
  if code != 0 {
    let message = stderr.text() catch { _ => "" }
    raise @cli.CliError::Invalid(
      "optimizer failed: " + message.trim().to_owned(),
    )
  }
  let result = @fs.read_file(output).binary() catch {
    e =>
      raise @cli.CliError::Io("optimizer produced no output: " + e.to_string())
  }
  // 先验证再返回，避免把损坏的产物写出去
  validate_core(result)
  result
}
