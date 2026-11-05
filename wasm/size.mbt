///|
/// 体积报告。只使用 raw section 与 core 指令模型，不引入额外依赖。
pub struct SizeSection {
  label : String
  payload : Int
  total : Int
  percent : Double
}

///|
pub struct FunctionSize {
  index : Int
  name : String
  bytes : Int
}

///|
pub struct SizeReport {
  file : String
  total : Int
  header : Int
  sections : Array[SizeSection]
  imported_functions : Int
  functions : Array[FunctionSize]
  call_edges : Int
  indirect_calls : Int
}

///|
fn percent(part : Int, total : Int) -> Double {
  if total == 0 {
    0.0
  } else {
    part.to_double() * 100.0 / total.to_double()
  }
}

///|
/// 解析 code section 的每个 body 长度（字节数在 size 前缀之后）。
fn code_body_sizes(data : Bytes, sections : Array[Section]) -> Array[Int] raise @cli.CliError {
  for section in sections {
    if section.id != 10 {
      continue
    }
    let cursor = Ref(section.payload)
    let end = section.payload + section.size
    let count = read_leb(data, cursor)
    let sizes : Array[Int] = []
    for _ in 0..<count {
      let size = read_leb(data, cursor)
      let body_start = cursor.val
      if body_start + size > end {
        raise @cli.CliError::Invalid("function body overruns the code section")
      }
      sizes.push(size)
      cursor.val = body_start + size
    }
    return sizes
  }
  []
}

///|
/// 生成报告。`top` 只影响文本输出的截断，JSON 总是包含全部函数。
pub fn size_report(data : Bytes, file : String) -> SizeReport raise @cli.CliError {
  let kind = detect_kind(data)
  let sections = scan_sections(data)
  let total = data.length()
  let size_sections : Array[SizeSection] = []
  for section in sections {
    let total_bytes = section.payload + section.size - section.start
    size_sections.push({
      label: section.label(kind),
      payload: section.size,
      total: total_bytes,
      percent: percent(total_bytes, total),
    })
  }
  if kind.is_component() {
    return {
      file,
      total,
      header: 8,
      sections: size_sections,
      imported_functions: 0,
      functions: [],
      call_edges: 0,
      indirect_calls: 0,
    }
  }
  let parsed = try @core_parser.parse_module(data) catch {
    e => raise @cli.CliError::Invalid("parse: " + e.to_string())
  }
  let mut imported = 0
  for declared in parsed.imports {
    match declared.desc {
      Func(_) => imported = imported + 1
      _ => ()
    }
  }
  let body_sizes = code_body_sizes(data, sections)
  let functions : Array[FunctionSize] = []
  for index, bytes in body_sizes {
    let absolute = imported + index
    functions.push({
      index: absolute,
      name: parsed.func_names.get(absolute).unwrap_or(""),
      bytes,
    })
  }
  let mut edges = 0
  let mut indirect = 0
  for code in parsed.codes {
    for instruction in code.body {
      match instruction {
        Call(_) | ReturnCall(_) => edges = edges + 1
        CallIndirect(_, _) | ReturnCallIndirect(_, _) | CallRef(_) | ReturnCallRef(_) =>
          indirect = indirect + 1
        _ => ()
      }
    }
  }
  {
    file,
    total,
    header: 8,
    sections: size_sections,
    imported_functions: imported,
    functions,
    call_edges: edges,
    indirect_calls: indirect,
  }
}

///|
pub fn size_text(report : SizeReport, top : Int) -> String {
  let out = StringBuilder()
  out.write_string("file " + report.file + "\n")
  out.write_string("total " + report.total.to_string() + " B\n")
  out.write_string("header " + report.header.to_string() + " B\n\n")
  out.write_string("sections\n")
  for section in report.sections {
    out.write_string(
      "  " +
      pad_right(section.label, 24) +
      pad_left(section.total.to_string(), 8) +
      " B  " +
      format_percent(section.percent) +
      "\n",
    )
  }
  if report.functions.is_empty() {
    return out.to_string()
  }
  let sorted = report.functions.copy()
  sorted.sort_by(fn(left, right) {
    if left.bytes != right.bytes {
      right.bytes - left.bytes
    } else {
      left.index - right.index
    }
  })
  let shown = if top <= 0 || top > sorted.length() { sorted.length() } else { top }
  out.write_string("\nfunctions (top " + shown.to_string() + " of " + sorted.length().to_string() + ")\n")
  for i = 0; i < shown; i = i + 1 {
    let function_ = sorted[i]
    let name = if function_.name.is_empty() { "(unnamed)" } else { function_.name }
    out.write_string(
      "  " +
      pad_left(function_.index.to_string(), 6) +
      "  " +
      pad_right(name, 32) +
      "  " +
      pad_left(function_.bytes.to_string(), 8) +
      " B\n",
    )
  }
  out.write_string(
    "\ncall graph: " +
    report.call_edges.to_string() +
    " direct edges, " +
    report.indirect_calls.to_string() +
    " indirect calls\n",
  )
  out.to_string()
}

///|
pub fn size_json(report : SizeReport) -> String {
  let out = StringBuilder()
  out.write_string("{\"file\":")
  out.write_string(json_string(report.file))
  out.write_string(",\"total\":")
  out.write_string(report.total.to_string())
  out.write_string(",\"header\":")
  out.write_string(report.header.to_string())
  out.write_string(",\"sections\":[")
  for i, section in report.sections {
    if i > 0 {
      out.write_string(",")
    }
    out.write_string("{\"label\":")
    out.write_string(json_string(section.label))
    out.write_string(",\"payload\":")
    out.write_string(section.payload.to_string())
    out.write_string(",\"total\":")
    out.write_string(section.total.to_string())
    out.write_string("}")
  }
  out.write_string("],\"imported_functions\":")
  out.write_string(report.imported_functions.to_string())
  out.write_string(",\"functions\":[")
  for i, function_ in report.functions {
    if i > 0 {
      out.write_string(",")
    }
    out.write_string("{\"index\":")
    out.write_string(function_.index.to_string())
    out.write_string(",\"name\":")
    out.write_string(json_string(function_.name))
    out.write_string(",\"bytes\":")
    out.write_string(function_.bytes.to_string())
    out.write_string("}")
  }
  out.write_string("],\"call_graph\":{\"direct\":")
  out.write_string(report.call_edges.to_string())
  out.write_string(",\"indirect\":")
  out.write_string(report.indirect_calls.to_string())
  out.write_string("}}")
  out.to_string()
}

///|
pub struct FunctionDelta {
  key : String
  name : String
  before : Int
  after : Int
  status : String
}

///|
pub struct SizeDiff {
  file : String
  baseline : String
  before_total : Int
  after_total : Int
  changes : Array[FunctionDelta]
}

///|
/// 函数按 name 匹配；没有名字时退回 `#index`。索引在两次构建间会漂移，
/// 名字匹配能避免把一次重排误报成大量增删。
fn function_key(function_ : FunctionSize) -> String {
  if function_.name.is_empty() {
    "#" + function_.index.to_string()
  } else {
    function_.name
  }
}

///|
fn function_map(report : SizeReport) -> Map[String, FunctionSize] {
  let map : Map[String, FunctionSize] = Map([])
  for function_ in report.functions {
    let key = function_key(function_)
    if !map.contains(key) {
      map.set(key, function_)
    }
  }
  map
}

///|
pub fn size_diff(current : SizeReport, baseline : SizeReport) -> SizeDiff {
  let before = function_map(baseline)
  let after = function_map(current)
  let changes : Array[FunctionDelta] = []
  for key, function_ in after {
    match before.get(key) {
      Some(old) => {
        if old.bytes != function_.bytes {
          changes.push({
            key,
            name: function_.name,
            before: old.bytes,
            after: function_.bytes,
            status: "changed",
          })
        }
      }
      None =>
        changes.push({
          key,
          name: function_.name,
          before: 0,
          after: function_.bytes,
          status: "added",
        })
    }
  }
  for key, function_ in before {
    if !after.contains(key) {
      changes.push({
        key,
        name: function_.name,
        before: function_.bytes,
        after: 0,
        status: "removed",
      })
    }
  }
  changes.sort_by(fn(left, right) {
    let left_delta = delta_of(left)
    let right_delta = delta_of(right)
    if left_delta != right_delta {
      right_delta - left_delta
    } else {
      left.key.compare(right.key)
    }
  })
  {
    file: current.file,
    baseline: baseline.file,
    before_total: baseline.total,
    after_total: current.total,
    changes,
  }
}

///|
fn delta_of(change : FunctionDelta) -> Int {
  change.after - change.before
}

///|
pub fn diff_text(diff : SizeDiff, top : Int) -> String {
  let out = StringBuilder()
  let total_delta = diff.after_total - diff.before_total
  out.write_string("file " + diff.file + "\n")
  out.write_string("baseline " + diff.baseline + "\n")
  out.write_string(
    "total " +
    diff.before_total.to_string() +
    " -> " +
    diff.after_total.to_string() +
    " (" +
    signed(total_delta) +
    ")\n",
  )
  if diff.changes.is_empty() {
    out.write_string("\nno function size changes\n")
    return out.to_string()
  }
  let shown = if top <= 0 || top > diff.changes.length() {
    diff.changes.length()
  } else {
    top
  }
  out.write_string("\nfunctions (top " + shown.to_string() + " of " + diff.changes.length().to_string() + ")\n")
  for i = 0; i < shown; i = i + 1 {
    let change = diff.changes[i]
    let name = if change.name.is_empty() { change.key } else { change.name }
    out.write_string(
      "  " +
      pad_right(change.status, 8) +
      "  " +
      pad_right(name, 32) +
      "  " +
      pad_left(signed(delta_of(change)), 9) +
      " B  (" +
      change.before.to_string() +
      " -> " +
      change.after.to_string() +
      ")\n",
    )
  }
  out.to_string()
}

///|
pub fn diff_json(diff : SizeDiff) -> String {
  let out = StringBuilder()
  out.write_string("{\"file\":")
  out.write_string(json_string(diff.file))
  out.write_string(",\"baseline\":")
  out.write_string(json_string(diff.baseline))
  out.write_string(",\"before_total\":")
  out.write_string(diff.before_total.to_string())
  out.write_string(",\"after_total\":")
  out.write_string(diff.after_total.to_string())
  out.write_string(",\"total_delta\":")
  out.write_string((diff.after_total - diff.before_total).to_string())
  out.write_string(",\"functions\":[")
  for i, change in diff.changes {
    if i > 0 {
      out.write_string(",")
    }
    out.write_string("{\"key\":")
    out.write_string(json_string(change.key))
    out.write_string(",\"name\":")
    out.write_string(json_string(change.name))
    out.write_string(",\"before\":")
    out.write_string(change.before.to_string())
    out.write_string(",\"after\":")
    out.write_string(change.after.to_string())
    out.write_string(",\"delta\":")
    out.write_string(delta_of(change).to_string())
    out.write_string(",\"status\":")
    out.write_string(json_string(change.status))
    out.write_string("}")
  }
  out.write_string("]}")
  out.to_string()
}

///|
fn signed(value : Int) -> String {
  if value > 0 {
    "+" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
pub struct FunctionLayout {
  /// 函数体第一条指令的绝对文件 offset（跳过 size 前缀与 locals 声明）
  start : Int
  /// 函数体字节数（locals + 表达式）
  size : Int
}

///|
/// 绝对函数索引 → 函数体位置。imported 函数占住前面的索引，但没有 body。
pub fn function_layout(data : Bytes, sections : Array[Section]) -> Map[Int, FunctionLayout] {
  let layout : Map[Int, FunctionLayout] = Map([])
  let mut imported = 0
  let parsed_body = try {
    Some(@core_parser.parse_module(data))
  } catch {
    _ => None
  }
  match parsed_body {
    Some(parsed) => {
      for declaration in parsed.imports {
        match declaration.desc {
          Func(_) => imported = imported + 1
          _ => ()
        }
      }
    }
    None => ()
  }
  for section in sections {
    if section.id != 10 {
      continue
    }
    let cursor = Ref(section.payload)
    let end = section.payload + section.size
    let count = read_leb(data, cursor) catch { _ => return layout }
    for index in 0..<count {
      let size = read_leb(data, cursor) catch { _ => return layout }
      let body_start = cursor.val
      if body_start + size > end {
        return layout
      }
      // body 的前若干个字节是 locals 声明；wasm 栈回溯的 offset 相对 body 起点，
      // 因此这里保留 body 起点，不尝试跳过 locals。
      layout.set(imported + index, { start: body_start, size })
      cursor.val = body_start + size
    }
  }
  layout
}
