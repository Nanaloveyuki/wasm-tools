///|
/// 统一的输入读取：`None` 或 `-` 表示 stdin。
pub async fn read_input(path : String?) -> Bytes raise CliError {
  match path {
    None =>
      @stdio.stdin.read_all() catch {
        e => raise CliError::Io(Error::to_string(e))
      }
    Some(p) =>
      if p == "-" {
        @stdio.stdin.read_all() catch {
          e => raise CliError::Io(Error::to_string(e))
        }
      } else {
        let exists = @fs.exists(p) catch {
          e => raise CliError::Io(p + ": " + e.to_string())
        }
        if !exists {
          raise CliError::Io("no such file: " + p)
        }
        @fs.read_binary(p) catch {
          e => raise CliError::Io(p + ": " + e.to_string())
        }
      }
  }
}

///|
/// 统一的输出写入：`None` 表示 stdout。
pub async fn write_output(path : String?, data : Bytes) -> Unit raise CliError {
  match path {
    None =>
      @stdio.stdout.write(data) catch {
        e => raise CliError::Io(Error::to_string(e))
      }
    Some("-") =>
      @stdio.stdout.write(data) catch {
        e => raise CliError::Io(Error::to_string(e))
      }
    Some(p) =>
      @fs.write_binary(p, data) catch {
        e => raise CliError::Io(p + ": " + e.to_string())
      }
  }
}

///|
/// 输出失败（例如 broken pipe）按 IO 错误上报，但调用方通常只关心退出码。
pub async fn write_stdout(text : String) -> Unit raise CliError {
  @stdio.stdout.text.write(text) catch {
    e => raise CliError::Io(Error::to_string(e))
  }
}

///|
pub async fn write_stderr(text : String) -> Unit raise CliError {
  @stdio.stderr.text.write(text) catch {
    e => raise CliError::Io(Error::to_string(e))
  }
}

///|
/// 错误路径专用：即使 stderr 不可写，也不能再抛错。
pub async fn write_stderr_lossy(text : String) -> Unit {
  let _ = @stdio.stderr.text.write(text) catch { _ => () }
  ()
}
