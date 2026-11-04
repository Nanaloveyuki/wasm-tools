///|
/// 统一的输入读取：`None` 或 `-` 表示 stdin。
pub async fn read_input(path : String?) -> Bytes raise CliError {
  match path {
    None => try @stdio.stdin.read_all().binary() catch {
      e => raise CliError::Io(e.to_string())
    }
    Some(p) => {
      if p == "-" {
        try @stdio.stdin.read_all().binary() catch {
          e => raise CliError::Io(e.to_string())
        }
      } else {
        let exists = try @fs.exists(p) catch {
          e => raise CliError::Io(p + ": " + e.to_string())
        }
        if !exists {
          raise CliError::Io("no such file: " + p)
        }
        try @fs.read_file(p).binary() catch {
          e => raise CliError::Io(p + ": " + e.to_string())
        }
      }
    }
  }
}

///|
/// 统一的输出写入：`None` 表示 stdout。
pub async fn write_output(path : String?, data : Bytes) -> Unit raise CliError {
  match path {
    None => try @stdio.stdout.write(data) catch {
      e => raise CliError::Io(e.to_string())
    }
    Some("-") => try @stdio.stdout.write(data) catch {
      e => raise CliError::Io(e.to_string())
    }
    Some(p) => try @fs.write_file(p, data) catch {
      e => raise CliError::Io(p + ": " + e.to_string())
    }
  }
}

///|
/// 输出失败（例如 broken pipe）按 IO 错误上报，但调用方通常只关心退出码。
pub async fn write_stdout(text : String) -> Unit raise CliError {
  try @stdio.stdout.write(text) catch {
    e => raise CliError::Io(e.to_string())
  }
}

///|
pub async fn write_stderr(text : String) -> Unit raise CliError {
  try @stdio.stderr.write(text) catch {
    e => raise CliError::Io(e.to_string())
  }
}

///|
/// 错误路径专用：即使 stderr 不可写，也不能再抛错。
pub async fn write_stderr_lossy(text : String) -> Unit {
  let _ = try @stdio.stderr.write(text) catch {
    _ => ()
  }
  ()
}
