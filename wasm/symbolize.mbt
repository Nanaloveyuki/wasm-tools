///|
/// 一个 `wasm-function[i]:0xoff` 的解析结果。
pub struct Symbolized {
  /// 输入中的函数索引；只给绝对 offset 时为 None
  function_index : Int?
  /// 函数名；name section 缺失时为 None
  name : String?
  /// 模块内的绝对字节 offset
  address : Int
  /// 函数体内偏移；只给绝对 offset 时按最近的函数推断
  function_offset : Int?
}

///|
/// MoonBit 的 wasm 崩溃栈形如 `wasm-function[16]:0x947`。
/// 解析这个形式，或直接解析十六进制绝对 offset。
pub fn parse_address(text : String) -> (Int?, Int) raise @cli.CliError {
  let trimmed = text.trim().to_owned()
  if trimmed.is_empty() {
    raise @cli.CliError::Usage("empty address")
  }
  if trimmed.has_prefix("wasm-function[") {
    let close = trimmed.find("]")
    match close {
      Some(index) => {
        let number = trimmed.get_view(start=14, end=index).unwrap_or("").to_owned()
        let function_index = try @str.parse_int(number) catch {
          _ => raise @cli.CliError::Usage("bad function index: " + number)
        }
        let rest = trimmed.get_view(start=index + 1).unwrap_or("").to_owned()
        let offset_text = if rest.has_prefix(":") {
          rest.get_view(start=1).unwrap_or("").to_owned()
        } else {
          rest
        }
        return (Some(function_index), parse_hex(offset_text))
      }
      None => raise @cli.CliError::Usage("missing ] in " + text)
    }
  }
  (None, parse_hex(trimmed))
}

///|
fn parse_hex(text : String) -> Int raise @cli.CliError {
  let mut value = 0
  let mut seen = false
  let digits = if text.has_prefix("0x") || text.has_prefix("0X") {
    text.get_view(start=2).unwrap_or("").to_owned()
  } else {
    text
  }
  for ch in digits {
    if ch == '_' {
      continue
    }
    let mut digit = 0
    if ch >= '0' && ch <= '9' {
      digit = ch.to_int() - '0'.to_int()
    } else if ch >= 'a' && ch <= 'f' {
      digit = ch.to_int() - 'a'.to_int() + 10
    } else if ch >= 'A' && ch <= 'F' {
      digit = ch.to_int() - 'A'.to_int() + 10
    } else {
      raise @cli.CliError::Usage("not a hex address: " + text)
    }
    value = value * 16 + digit
    seen = true
  }
  if !seen {
    raise @cli.CliError::Usage("not a hex address: " + text)
  }
  value
}

///|
/// 把崩溃栈地址映射到函数名与函数内偏移。
///
/// MoonBit 的 wasm 回溯形如 `wasm-function[34]:0xd8d`，其中 `0xd8d` 是
/// **模块内绝对字节偏移**，不是函数内偏移（实测两个崩溃点都落在对应函数体内）。
/// 没有 DWARF 时，这是 MoonBit wasm 能提供的最完整信息。
pub fn symbolize(data : Bytes, address : String) -> Symbolized raise @cli.CliError {
  let (index, absolute) = parse_address(address)
  let sections = scan_sections(data)
  let views = custom_views(data, sections)
  let mut names : Map[Int, String] = Map([])
  for view in views {
    if view.name == "name" {
      names = function_names(data, view)
    }
  }
  let layout = function_layout(data, sections)
  // 栈里的 function index 与 offset 应互相印证；不一致时以 offset 定位为准，
  // 但仍保留栈给出的索引，方便发现运行时或工具版本差异。
  let containing : (Int, FunctionLayout)? = find_function(layout, absolute)
  let reported_index = match index {
    Some(value) => Some(value)
    None =>
      match containing {
        Some((function_index, _)) => Some(function_index)
        None => None
      }
  }
  let function_offset = match containing {
    Some((_, entry)) => Some(absolute - entry.start)
    None => None
  }
  let name = match reported_index {
    Some(function_index) => names.get(function_index)
    None => None
  }
  {
    function_index: reported_index,
    name,
    address: absolute,
    function_offset,
  }
}

///|
fn find_function(
  layout : Map[Int, FunctionLayout],
  absolute : Int,
) -> (Int, FunctionLayout)? {
  let mut found : (Int, FunctionLayout)? = None
  for function_index, entry in layout {
    if absolute >= entry.start && absolute < entry.start + entry.size {
      found = Some((function_index, entry))
    }
  }
  found
}

///|
pub fn symbolize_text(symbol : Symbolized) -> String {
  let out = StringBuilder()
  match symbol.function_index {
    Some(index) => out.write_string("function " + index.to_string() + "\n")
    None => out.write_string("function (not found)\n")
  }
  match symbol.name {
    Some(name) => out.write_string("name " + name + "\n")
    None => out.write_string("name (unnamed)\n")
  }
  out.write_string("address 0x" + hex(symbol.address) + "\n")
  match symbol.function_offset {
    Some(offset) => out.write_string("offset 0x" + hex(offset) + "\n")
    None => out.write_string("offset (unknown)\n")
  }
  out.to_string()
}

///|
pub fn symbolize_json(symbol : Symbolized) -> String {
  let out = StringBuilder()
  out.write_string("{\"function\":")
  match symbol.function_index {
    Some(index) => out.write_string(index.to_string())
    None => out.write_string("null")
  }
  out.write_string(",\"name\":")
  match symbol.name {
    Some(name) => out.write_string(json_string(name))
    None => out.write_string("null")
  }
  out.write_string(",\"address\":")
  out.write_string(symbol.address.to_string())
  out.write_string(",\"function_offset\":")
  match symbol.function_offset {
    Some(offset) => out.write_string(offset.to_string())
    None => out.write_string("null")
  }
  out.write_string("}")
  out.to_string()
}

///|
fn hex(value : Int) -> String {
  if value == 0 {
    return "0"
  }
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  let mut remaining = value
  let buffer : Array[Char] = []
  while remaining > 0 {
    let digit = remaining % 16
    buffer.push(digits.get_char(digit).unwrap_or('0'))
    remaining = remaining / 16
  }
  for i = buffer.length() - 1; i >= 0; i = i - 1 {
    out.write_char(buffer[i])
  }
  out.to_string()
}
