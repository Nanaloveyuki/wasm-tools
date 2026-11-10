///|
/// CLI 层的统一错误。上游库的字符串错误只在这里归类，命令层不再区分来源。
pub(all) suberror CliError {
  Usage(String)
  Io(String)
  Invalid(String)
  Unsupported(String)
  Schema(String)
}

///|
pub fn CliError::message(self : CliError) -> String {
  match self {
    Usage(m) => m
    Io(m) => m
    Invalid(m) => m
    Unsupported(m) => m
    Schema(m) => m
  }
}

///|
pub fn CliError::exit_code(self : CliError) -> Int32 {
  match self {
    Usage(_) | Io(_) | Schema(_) => 2
    Invalid(_) | Unsupported(_) => 1
  }
}
