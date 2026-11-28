///|
/// 二进制层：不依赖任何 wasm 模型，只做原始字节的 section 扫描与重建。
/// 所有越界都转成 `CliError`，保证任意输入都不会 panic。
pub struct Section {
  id : Int32
  /// section 起始偏移（含 id 字节）
  start : Int32
  /// payload 起始偏移（跳过后随的 LEB 长度）
  payload : Int32
  /// payload 字节数
  size : Int32
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
pub fn read_leb(data : Bytes, cursor : Ref[Int32]) -> Int32 raise @cli.CliError {
  read_leb_until(data, cursor, data.length())
}

///|
fn read_leb_until(
  data : Bytes,
  cursor : Ref[Int32],
  end : Int32,
) -> Int32 raise @cli.CliError {
  let mut result = 0
  let mut shift = 0
  while true {
    let pos = cursor.val
    if pos < 0 || pos >= end || pos >= data.length() {
      raise @cli.CliError::Invalid(
        "truncated LEB128 at offset " + pos.to_string(),
      )
    }
    let byte = data[pos].to_int()
    cursor.val = pos + 1
    if shift == 28 && (byte & 0xf0) != 0 {
      raise @cli.CliError::Invalid(
        "LEB128 exceeds 32 bits at offset " + pos.to_string(),
      )
    }
    result = result | ((byte & 0x7f) << shift)
    if (byte & 0x80) == 0 {
      break
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
  ignore(detect_kind(data))
  let sections : Array[Section] = []
  let cursor : Ref[Int32] = Ref(8)
  while cursor.val < data.length() {
    let start = cursor.val
    let id = data[start].to_int()
    cursor.val = start + 1
    let size = read_leb(data, cursor)
    let payload = cursor.val
    if size > data.length() - payload {
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
    let end = payload + size
    let name = if id == 0 {
      let name_cursor : Ref[Int32] = Ref(payload)
      Some(read_name_until(data, name_cursor, end))
    } else {
      None
    }
    sections.push({ id, start, payload, size, name, })
    cursor.val = end
  }
  sections
}

///|
fn read_name_until(
  data : Bytes,
  cursor : Ref[Int32],
  end : Int32,
) -> String raise @cli.CliError {
  let len = read_leb_until(data, cursor, end)
  let start = cursor.val
  guard end <= data.length() && len <= end - start else {
    raise @cli.CliError::Invalid("name length overruns its payload")
  }
  cursor.val = start + len
  @utf8.decode(data.exact_view(start~, end=cursor.val)) catch {
    _ => raise @cli.CliError::Invalid("name is not valid UTF-8")
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
  let out = @buffer.Buffer()
  out.write_bytesview(header[:])
  for piece in pieces {
    out.write_bytesview(piece[:])
  }
  out.to_bytes()
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
