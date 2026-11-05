///|
/// custom section 的只读视图：定位 payload 内部偏移，供 metadata 使用。
pub struct CustomView {
  name : String
  /// section payload 起点（section 名之后）
  body : Int32
  /// section payload 结束（不含）
  end : Int32
}

///|
pub fn custom_views(
  data : Bytes,
  sections : Array[Section],
) -> Array[CustomView] raise @cli.CliError {
  let views : Array[CustomView] = []
  for section in sections {
    if section.id != 0 {
      continue
    }
    let name = section.name.unwrap_or("")
    let cursor : Ref[Int32] = Ref(section.payload)
    let name_len = read_leb(data, cursor)
    let body = cursor.val + name_len
    let end = section.payload + section.size
    if body > end {
      raise @cli.CliError::Invalid(
        "custom section \"" + name + "\" is malformed",
      )
    }
    views.push({ name, body, end, })
  }
  views
}

///|
pub fn read_name_public(
  data : Bytes,
  cursor : Ref[Int32],
) -> String raise @cli.CliError {
  let len = read_leb(data, cursor)
  let start = cursor.val
  if start + len > data.length() {
    raise @cli.CliError::Invalid("name length overruns the input")
  }
  cursor.val = start + len
  match data.get_view(start~, end=start + len) {
    Some(view) => @utf8.decode_lossy(view)
    None => ""
  }
}

///|
/// `name` custom section 的 module 名（subsection 0）。
pub fn name_section_module(
  data : Bytes,
  view : CustomView,
) -> String? raise @cli.CliError {
  let cursor : Ref[Int32] = Ref(view.body)
  while cursor.val < view.end {
    let id = read_leb(data, cursor)
    let size = read_leb(data, cursor)
    let start = cursor.val
    if start + size > view.end {
      raise @cli.CliError::Invalid(
        "name section subsection overruns its payload",
      )
    }
    if id == 0 {
      let inner : Ref[Int32] = Ref(start)
      return Some(read_name_public(data, inner))
    }
    cursor.val = start + size
  }
  None
}

///|
/// `name` custom section 的 function 名条目数（subsection 1）。
pub fn name_section_function_count(
  data : Bytes,
  view : CustomView,
) -> Int32 raise @cli.CliError {
  let cursor : Ref[Int32] = Ref(view.body)
  while cursor.val < view.end {
    let id = read_leb(data, cursor)
    let size = read_leb(data, cursor)
    let start = cursor.val
    if start + size > view.end {
      raise @cli.CliError::Invalid(
        "name section subsection overruns its payload",
      )
    }
    if id == 1 {
      let inner : Ref[Int32] = Ref(start)
      return read_leb(data, inner)
    }
    cursor.val = start + size
  }
  0
}

///|
/// producers section 的一条 field。
pub struct ProducerField {
  name : String
  values : Array[(String, String)]
}

///|
/// 解析 `producers` custom section：vec(field_name, vec(name, version))。
pub fn producers(
  data : Bytes,
  view : CustomView,
) -> Array[ProducerField] raise @cli.CliError {
  let result : Array[ProducerField] = []
  let cursor : Ref[Int32] = Ref(view.body)
  let fields = read_leb(data, cursor)
  for _ in 0..<fields {
    let name = read_name_public(data, cursor)
    let count = read_leb(data, cursor)
    let values : Array[(String, String)] = []
    for _ in 0..<count {
      let key = read_name_public(data, cursor)
      let version = read_name_public(data, cursor)
      values.push((key, version))
    }
    result.push({ name, values, })
  }
  result
}

///|
/// `name` section 的函数名表（subsection 1）。索引是绝对函数索引。
pub fn function_names(
  data : Bytes,
  view : CustomView,
) -> Map[Int32, String] raise @cli.CliError {
  let names : Map[Int32, String] = Map([])
  let cursor : Ref[Int32] = Ref(view.body)
  while cursor.val < view.end {
    let id = read_leb(data, cursor)
    let size = read_leb(data, cursor)
    let start = cursor.val
    if start + size > view.end {
      raise @cli.CliError::Invalid(
        "name section subsection overruns its payload",
      )
    }
    if id == 1 {
      let inner : Ref[Int32] = Ref(start)
      let count = read_leb(data, inner)
      for _ in 0..<count {
        let index = read_leb(data, inner)
        let name = read_name_public(data, inner)
        names.set(index, name)
      }
      return names
    }
    cursor.val = start + size
  }
  names
}
