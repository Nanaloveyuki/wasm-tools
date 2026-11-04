///|
pub async fn cmd_parse(args : Array[String]) -> Int raise @cli.CliError {
  let options = @cli.parse_options(args)
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm parse [OPTIONS] [FILE]\n\nParse WAT into a wasm binary.\n",
    )
    return 0
  }
  let data = @cli.read_input(options.input)
  let text = try @utf8.decode(data.exact_view()) catch {
    _ => raise @cli.CliError::Invalid("input is not valid UTF-8")
  }
  let binary = if is_component_wat(text) {
    @wasm.component_wat_to_binary(text)
  } else {
    @wasm.wat_to_core(text)
  }
  @cli.write_output(options.output, binary)
  0
}

///|
/// 组件文本的顶层关键字是 `component`；core 文本是 `module` 或裸指令。
pub fn is_component_wat(text : String) -> Bool {
  let mut index = 0
  while index < text.length() {
    let ch = text.get_char(index)
    match ch {
      Some(c) => {
        if c == '(' {
          let mut probe = index + 1
          while probe < text.length() {
            match text.get_char(probe) {
              Some(p) => {
                if p == ' ' || p == '\n' || p == '\t' || p == '\r' {
                  probe = probe + 1
                  continue
                }
              }
              None => break
            }
            let rest = text.get_view(start=probe)
            match rest {
              Some(view) => return view.has_prefix("component")
              None => return false
            }
          }
          return false
        } else if c == ';' {
          while index < text.length() {
            match text.get_char(index) {
              Some(inner) => {
                index = index + 1
                if inner == '\n' {
                  break
                }
              }
              None => break
            }
          }
        } else if c == ' ' || c == '\n' || c == '\t' || c == '\r' {
          index = index + 1
        } else {
          return false
        }
      }
      None => break
    }
  }
  false
}
