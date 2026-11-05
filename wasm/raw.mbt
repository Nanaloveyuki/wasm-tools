///|
/// 二进制层：不依赖任何 wasm 模型，只做原始字节的 section 扫描与重建。
/// 所有越界都转成 `CliError`，保证任意输入都不会 panic。
pub struct Section {
  id : Int
  /// section 起始偏移（含 id 字节）
  start : Int
  /// payload 起始偏移（跳过后随的 LEB 长度）
  payload : Int
  /// payload 字节数
  size : Int
  /// custom section 的名字；非 custom section 为 None
  name : String?
}

///|
/// core 与 component 的 section id 空间不同，标签必须由调用方给出类型。
pub fn Section::label(self : Section, kind : InputKind) -> String {
  let base = section_name(kind, self.id)
  match self.name {
    Some(name) => base + " \"" + name + "\""
    None => base
  }
}

///|
pub fn read_leb(data : Bytes, cursor : Ref[Int]) -> Int raise @cli.CliError {
  let mut result = 0
  let mut shift = 0
  let mut count = 0
  while true {
    let pos = cursor.val
    if pos >= data.length() {
      raise @cli.CliError::Invalid("truncated LEB128 at offset " + pos.to_string())
    }
    let byte = data[pos].to_int()
    cursor.val = pos + 1
    result = result | ((byte & 0x7f) << shift)
    count = count + 1
    if (byte & 0x80) == 0 {
      break
    }
    if count >= 5 {
      raise @cli.CliError::Invalid("LEB128 exceeds 32 bits at offset " + pos.to_string())
    }
    shift = shift + 7
  }
  if result < 0 {
    raise @cli.CliError::Invalid("u32 value out of range")
  }
  result
}

///|
/// 扫描顶层 section 表。只做结构切分，不解释内容。
pub fn scan_sections(data : Bytes) -> Array[Section] raise @cli.CliError {
  if data.length() < 8 {
    raise @cli.CliError::Invalid("input is shorter than the 8-byte wasm header")
  }
  if data[0] != b'\x00' ||
    data[1] != b'a' ||
    data[2] != b's' ||
    data[3] != b'm' {
    raise @cli.CliError::Invalid("missing wasm magic header")
  }
  let version = data[4].to_int() | (data[5].to_int() << 8)
  if version != 1 && version != 0x0d {
    raise @cli.CliError::Invalid("unsupported wasm version " + version.to_string())
  }
  let sections : Array[Section] = []
  let cursor : Ref[Int] = Ref(8)
  while cursor.val < data.length() {
    let start = cursor.val
    let id = data[start].to_int()
    cursor.val = start + 1
    let size = read_leb(data, cursor)
    let payload = cursor.val
    if payload + size > data.length() {
      raise @cli.CliError::Invalid(
        "section " +
        id.to_string() +
        " at " +
        start.to_string() +
        " claims " +
        size.to_string() +
        " bytes, past end of input",
      )
    }
    let name = if id == 0 {
      let name_cursor : Ref[Int] = Ref(payload)
      let name_len = read_leb(data, name_cursor)
      let name_start = name_cursor.val
      if name_start + name_len > payload + size {
        raise @cli.CliError::Invalid("custom section name overruns its payload")
      }
      Some(decode_utf8(data, name_start, name_len))
    } else {
      None
    }
    sections.push({ id, start, payload, size, name })
    cursor.val = payload + size
  }
  sections
}

///|
fn decode_utf8(data : Bytes, start : Int, length : Int) -> String {
  match data.get_view(start~, end=start + length) {
    Some(view) => @utf8.decode_lossy(view)
    None => ""
  }
}

///|
/// 一段 section 的完整原始字节（含 id 与长度前缀）。
pub fn section_bytes(data : Bytes, section : Section) -> Bytes {
  let end = section.payload + section.size
  data.exact_view(start=section.start, end~).to_owned()
}

///|
/// 拼接 header 与给定 section 的原始字节，得到新的模块。
pub fn rebuild(header : Bytes, pieces : Array[Bytes]) -> Bytes {
  let mut out = header
  for piece in pieces {
    out = out + piece
  }
  out
}

///|
/// 删除指定的 custom section，其余字节原样保留。
pub fn strip_custom_sections(
  data : Bytes,
  sections : Array[Section],
  drop : (String) -> Bool,
) -> Bytes {
  let pieces : Array[Bytes] = []
  for section in sections {
    let keep = if section.id != 0 {
      true
    } else {
      match section.name {
        Some(name) => !drop(name)
        None => true
      }
    }
    if keep {
      pieces.push(section_bytes(data, section))
    }
  }
  rebuild(data.exact_view(start=0, end=8).to_owned(), pieces)
}
