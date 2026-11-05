///|
/// 子命令分发。命令只负责参数与输出格式，二进制细节在 `wasm` 包。
pub async fn run(argv : Array[String]) -> Int {
  let args = argv[1:].to_owned()
  if args.is_empty() {
    @cli.write_stdout(@cli.help_text())
    return 0
  }
  let result = try {
    let command = args[0]
    let rest = args[1:].to_owned()
    dispatch(command, rest)
  } catch {
    @cli.CliError::Usage(message) => {
      @cli.write_stderr_lossy(@cli.TOOL_NAME + ": " + message + "\n")
      @cli.write_stderr_lossy("Run `" + @cli.TOOL_NAME + " --help` for usage.\n")
      return 2
    }
    @cli.CliError::Io(message) => {
      @cli.write_stderr_lossy(@cli.TOOL_NAME + ": " + message + "\n")
      return 2
    }
    @cli.CliError::Invalid(message) => {
      @cli.write_stderr_lossy(@cli.TOOL_NAME + ": " + message + "\n")
      return 1
    }
    @cli.CliError::Unsupported(message) => {
      @cli.write_stderr_lossy(@cli.TOOL_NAME + ": " + message + "\n")
      return 1
    }
  }
  result
}

///|
async fn dispatch(command : String, args : Array[String]) -> Int raise @cli.CliError {
  match command {
    "-h" | "--help" | "help" => {
      @cli.write_stdout(@cli.help_text())
      0
    }
    "-V" | "--version" | "version" => {
      @cli.write_stdout(@cli.TOOL_NAME + " " + @cli.VERSION + "\n")
      0
    }
    "validate" => cmd_validate(args)
    "print" => cmd_print(args)
    "parse" => cmd_parse(args)
    "dump" => cmd_dump(args)
    "strip" => cmd_strip(args)
    "metadata" => cmd_metadata(args)
    "size" => cmd_size(args)
    "opt" => cmd_opt(args)
    "compose" => cmd_compose(args)
    "symbolize" => cmd_symbolize(args)
    "component" => cmd_component(args)
    _ => {
      raise @cli.CliError::Usage("unknown command: " + command)
    }
  }
}
