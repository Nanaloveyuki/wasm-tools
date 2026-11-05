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
