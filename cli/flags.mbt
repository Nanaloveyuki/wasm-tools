///|
/// 与 `reject_unknown` 相同，但直接接收剩余选项数组，便于子命令重组后再校验。
pub fn reject_unknown_extra(extra : Array[String]) -> Unit raise CliError {
  if extra.length() > 0 {
    raise CliError::Usage("unknown option: " + extra[0])
  }
}

///|
/// 校验 `options.extra` 为空；各子命令在解析完自己的选项后调用。
pub fn reject_unknown(options : Options) -> Unit raise CliError {
  if options.extra.length() > 0 {
    raise CliError::Usage("unknown option: " + options.extra[0])
  }
}

///|
/// 从 `extra` 中取出带值的选项，其余保留。`name` 可以是 `--keep` 这类长选项。
pub fn take_value(
  options : Options,
  name : String,
) -> Array[String] raise CliError {
  let values : Array[String] = []
  let rest : Array[String] = []
  let mut index = 0
  while index < options.extra.length() {
    let arg = options.extra[index]
    if arg == name {
      index = index + 1
      if index >= options.extra.length() {
        raise CliError::Usage("missing value for " + name)
      }
      values.push(options.extra[index])
    } else if arg.has_prefix(name + "=") {
      match arg.get_view(start=name.length() + 1) {
        Some(view) => values.push(view.to_owned())
        None => ()
      }
    } else {
      rest.push(arg)
    }
    index = index + 1
  }
  options.extra = rest
  values
}

///|
/// 移除一个不带值的开关；返回是否出现过。
pub fn take_flag(options : Options, name : String) -> Bool {
  let rest : Array[String] = []
  let mut found = false
  for arg in options.extra {
    if arg == name {
      found = true
    } else {
      rest.push(arg)
    }
  }
  options.extra = rest
  found
}
