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
/// 组件文本的顶层形式是 `(component ...)`，core 是 `(module ...)` 或裸指令。
/// 只跳过空白和注释，不看文件扩展名。
pub fn is_component_wat(text : String) -> Bool {
  let index = skip_space_and_comments(text, 0)
  if index >= text.length() {
    return false
  }
  let mut cursor = index
  match text.get_char(cursor) {
    Some(c) =>
      if c != '(' {
        return false
      }
    None => return false
  }
  cursor = cursor + 1
  let keyword = skip_space_and_comments(text, cursor)
  match text.get_view(start=keyword) {
    Some(view) => view.has_prefix("component")
    None => false
  }
}

///|
/// 跳过空白、`;;` 行注释与 `(; ... ;)` 块注释；遇到其它字符返回当前位置。
fn skip_space_and_comments(text : String, start : Int) -> Int {
  let mut index = start
  while index < text.length() {
    match text.get_char(index) {
      Some(c) => {
        if c == ' ' || c == '\n' || c == '\t' || c == '\r' {
          index = index + 1
        } else if c == ';' {
          index = index + 1
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
        } else if c == '(' {
          match text.get_char(index + 1) {
            Some(';') =>
              match skip_block_comment(text, index + 2) {
                Some(next) => index = next
                None => return text.length()
              }
            _ => return index
          }
        } else {
          return index
        }
      }
      None => return index
    }
  }
  index
}

///|
/// 从 `(;` 之后开始跳过块注释（支持嵌套），返回结束位置。
fn skip_block_comment(text : String, start : Int) -> Int? {
  let mut depth = 1
  let mut index = start
  while index + 1 < text.length() {
    match (text.get_char(index), text.get_char(index + 1)) {
      (Some('('), Some(';')) => {
        depth = depth + 1
        index = index + 2
      }
      (Some(';'), Some(')')) => {
        depth = depth - 1
        index = index + 2
        if depth == 0 {
          return Some(index)
        }
      }
      _ => index = index + 1
    }
  }
  None
}
