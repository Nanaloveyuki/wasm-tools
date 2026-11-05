///|
pub const TOOL_NAME : String = "wsm"

///|
pub const VERSION : String = "0.3.0"


///|
/// 所有子命令共享的输入输出选项。`input = None` 表示 stdin。
pub struct Options {
  mut input : String?
  mut output : String?
  mut json : Bool
  mut help : Bool
  /// 子命令自有选项（含其值），供 `strip`/`dump` 再解析
  mut extra : Array[String]
}

///|
pub fn Options::new() -> Options {
  { input: None, output: None, json: false, help: false, extra: [] }
}

///|
/// 解析通用选项。`value_options` 列出子命令中需要取值的选项名，
/// 它们的值不会被误当作输入文件。未知选项原样留在 `extra`。
pub fn parse_options(
  args : Array[String],
  allow_json? : Bool = false,
  value_options? : Array[String] = [],
) -> Options raise CliError {
  let options = Options::new()
  let mut index = 0
  let mut positional_only = false
  while index < args.length() {
    let arg = args[index]
    if !positional_only && arg == "--" {
      positional_only = true
    } else if !positional_only && (arg == "-h" || arg == "--help") {
      options.help = true
    } else if !positional_only && arg == "--json" {
      if !allow_json {
        raise CliError::Usage("--json is not supported by this command")
      }
      options.json = true
    } else if !positional_only && (arg == "-o" || arg == "--output") {
      index = index + 1
      if index >= args.length() {
        raise CliError::Usage("missing value for " + arg)
      }
      options.output = Some(args[index])
    } else if !positional_only && arg.has_prefix("-") && arg != "-" {
      options.extra.push(arg)
      if is_value_option(arg, value_options) {
        index = index + 1
        if index >= args.length() {
          raise CliError::Usage("missing value for " + arg)
        }
        options.extra.push(args[index])
      }
    } else if options.input is None {
      options.input = Some(arg)
    } else {
      options.extra.push(arg)
    }
    index = index + 1
  }
  options
}

///|
fn is_value_option(arg : String, value_options : Array[String]) -> Bool {
  for name in value_options {
    if arg == name {
      return true
    }
    if arg.has_prefix(name + "=") {
      return false
    }
  }
  false
}
