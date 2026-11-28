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
    let end = section.payload + section.size
    let name_len = read_leb_until(data, cursor, end)
    guard name_len <= end - cursor.val else {
      raise @cli.CliError::Invalid(
        "custom section \"" + name + "\" is malformed",
      )
    }
    let body = cursor.val + name_len
    views.push({ name, body, end, })
  }
  views
}

///|
pub fn read_name_public(
  data : Bytes,
  cursor : Ref[Int32],
) -> String raise @cli.CliError {
  read_name_until(data, cursor, data.length())
}

///|
/// `name` custom section 的 module 名（subsection 0）。
pub fn name_section_module(
  data : Bytes,
  view : CustomView,
) -> String? raise @cli.CliError {
  guard name_subsection(data, view, 0) is Some((start, end)) else {
    return None
  }
  let cursor = Ref(start)
  let name = read_name_until(data, cursor, end)
  require_payload_end(cursor, end)
  Some(name)
}

///|
fn name_subsection(
  data : Bytes,
  view : CustomView,
  target : Int32,
) -> (Int32, Int32)? raise @cli.CliError {
  let cursor : Ref[Int32] = Ref(view.body)
  while cursor.val < view.end {
    let id = read_leb_until(data, cursor, view.end)
    let size = read_leb_until(data, cursor, view.end)
    let start = cursor.val
    if size > view.end - start || size > data.length() - start {
      raise @cli.CliError::Invalid(
        "name section subsection overruns its payload",
      )
    }
    let end = start + size
    if id == target {
      return Some((start, end))
    }
    cursor.val = end
  }
  None
}

///|
/// `name` custom section 的 function 名条目数（subsection 1）。
pub fn name_section_function_count(
  data : Bytes,
  view : CustomView,
) -> Int32 raise @cli.CliError {
  read_function_names(data, view).0
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
  let fields = read_leb_until(data, cursor, view.end)
  for _ in 0..<fields {
    let name = read_name_until(data, cursor, view.end)
    let count = read_leb_until(data, cursor, view.end)
    let values : Array[(String, String)] = []
    for _ in 0..<count {
      let key = read_name_until(data, cursor, view.end)
      let version = read_name_until(data, cursor, view.end)
      values.push((key, version))
    }
    result.push({ name, values, })
  }
  require_payload_end(cursor, view.end)
  result
}

///|
/// `name` section 的函数名表（subsection 1）。索引是绝对函数索引。
pub fn function_names(
  data : Bytes,
  view : CustomView,
) -> Map[Int32, String] raise @cli.CliError {
  read_function_names(data, view).1
}

///|
fn read_function_names(
  data : Bytes,
  view : CustomView,
) -> (Int32, Map[Int32, String]) raise @cli.CliError {
  let names : Map[Int32, String] = Map([])
  guard name_subsection(data, view, 1) is Some((start, end)) else {
    return (0, names)
  }
  let cursor = Ref(start)
  let count = read_leb_until(data, cursor, end)
  for _ in 0..<count {
    let index = read_leb_until(data, cursor, end)
    let name = read_name_until(data, cursor, end)
    names.set(index, name)
  }
  require_payload_end(cursor, end)
  (count, names)
}

///|
fn require_payload_end(
  cursor : Ref[Int32],
  end : Int32,
) -> Unit raise @cli.CliError {
  if cursor.val != end {
    raise @cli.CliError::Invalid("unexpected trailing bytes in payload")
  }
}
