///|
/// 二进制结构与指令报告。`dump`/`metadata` 共用这里的格式化逻辑。
pub fn dump_text(
  data : Bytes,
  sections : Array[Section],
  kind : InputKind,
  instructions : Bool,
) -> String raise @cli.CliError {
  let out = StringBuilder()
  let subject = if kind.is_component() { "component" } else { "module" }
  out.write_string(subject + " " + data.length().to_string() + " bytes\n")
  out.write_string("offset  end     size    section\n")
  for section in sections {
    let size = section.size
    out.write_string(
      pad_left(section.start.to_string(), 6) +
      "  " +
      pad_left((section.payload + section.size).to_string(), 6) +
      "  " +
      pad_left(size.to_string(), 6) +
      "  " +
      section.label(kind) +
      "\n",
    )
  }
  if instructions {
    out.write_string("\ninstructions\n")
    out.write_string(dump_instructions(data))
  }
  out.to_string()
}

///|
pub fn dump_json(
  data : Bytes,
  sections : Array[Section],
  kind : InputKind,
  instructions : Bool,
) -> String raise @cli.CliError {
  let out = StringBuilder()
  out.write_string("{\"bytes\":")
  out.write_string(data.length().to_string())
  out.write_string(",\"sections\":[")
  let mut first = true
  for section in sections {
    if !first {
      out.write_string(",")
    }
    first = false
    out.write_string("{\"id\":")
    out.write_string(section.id.to_string())
    out.write_string(",\"kind\":")
    out.write_string(json_string(section_name(kind, section.id)))
    match section.name {
      Some(name) => {
        out.write_string(",\"name\":")
        out.write_string(json_string(name))
      }
      None => ()
    }
    out.write_string(",\"offset\":")
    out.write_string(section.start.to_string())
    out.write_string(",\"payload\":")
    out.write_string(section.payload.to_string())
    out.write_string(",\"size\":")
    out.write_string(section.size.to_string())
    out.write_string(",\"total\":")
    out.write_string(section.size.to_string())
    out.write_string("}")
  }
  out.write_string("]")
  if instructions {
    out.write_string(",\"instructions\":[")
    out.write_string(instructions_json(data))
    out.write_string("]")
  }
  out.write_string("}")
  out.to_string()
}

///|
/// 逐函数、逐指令的 offset 列表。只对 core module 有效。
fn dump_instructions(data : Bytes) -> String raise @cli.CliError {
  match detect_kind(data) {
    Component => "  (component: instruction listing is not supported)\n"
    CoreModule => {
      let (parsed, sources) = @core_parser.parse_module_with_sources(data) catch {
        e => raise @cli.CliError::Invalid("parse: " + e.to_string())
      }
      let out = StringBuilder()
      let imported = parsed.funcs.length()
      for index = 0; index < parsed.codes.length(); index = index + 1 {
        let absolute = imported + index
        let name = parsed.func_names.get(absolute).unwrap_or("")
        out.write_string(
          "func " +
          absolute.to_string() +
          (if name.is_empty() { "" } else { " " + name }) +
          "\n",
        )
        let code = parsed.codes[index]
        let source = if index < sources.length() { sources[index] } else { [] }
        for i = 0; i < code.body.length(); i = i + 1 {
          let offset = if i < source.length() {
            source[i].byte_offset.to_string()
          } else {
            "?"
          }
          out.write_string(
            "  @" +
            offset +
            "  " +
            concise_instruction(code.body[i].to_string()) +
            "\n",
          )
        }
      }
      out.to_string()
    }
  }
}

///|
fn instructions_json(data : Bytes) -> String raise @cli.CliError {
  match detect_kind(data) {
    Component => ""
    CoreModule => {
      let (parsed, sources) = @core_parser.parse_module_with_sources(data) catch {
        e => raise @cli.CliError::Invalid("parse: " + e.to_string())
      }
      let out = StringBuilder()
      let imported = parsed.funcs.length()
      let mut first = true
      for index = 0; index < parsed.codes.length(); index = index + 1 {
        let absolute = imported + index
        let name = parsed.func_names.get(absolute)
        if !first {
          out.write_string(",")
        }
        first = false
        out.write_string("{\"func\":")
        out.write_string(absolute.to_string())
        match name {
          Some(value) => {
            out.write_string(",\"name\":")
            out.write_string(json_string(value))
          }
          None => ()
        }
        out.write_string(",\"ops\":[")
        let code = parsed.codes[index]
        let source = if index < sources.length() { sources[index] } else { [] }
        for i = 0; i < code.body.length(); i = i + 1 {
          if i > 0 {
            out.write_string(",")
          }
          out.write_string("{\"offset\":")
          out.write_string(
            if i < source.length() {
              source[i].byte_offset.to_string()
            } else {
              "-1"
            },
          )
          out.write_string(",\"op\":")
          out.write_string(
            json_string(concise_instruction(code.body[i].to_string())),
          )
          out.write_string("}")
        }
        out.write_string("]}")
      }
      out.to_string()
    }
  }
}

///|
pub fn metadata_text(
  data : Bytes,
  kind : InputKind,
  json : Bool,
) -> String raise @cli.CliError {
  let sections = scan_sections(data)
  let views = custom_views(data, sections)
  let mut module_name : String? = None
  let mut function_count = 0
  let mut producer_fields : Array[ProducerField] = []
  let names : Array[String] = []
  for view in views {
    names.push(view.name)
    match view.name {
      "name" => {
        module_name = name_section_module(data, view)
        function_count = name_section_function_count(data, view)
      }
      "producers" => producer_fields = producers(data, view)
      _ => ()
    }
  }
  if json {
    let out = StringBuilder()
    out.write_string("{\"custom_sections\":[")
    for i, name in names {
      if i > 0 {
        out.write_string(",")
      }
      out.write_string(json_string(name))
    }
    out.write_string("],\"module_name\":")
    match module_name {
      Some(value) => out.write_string(json_string(value))
      None => out.write_string("null")
    }
    out.write_string(",\"function_names\":")
    out.write_string(function_count.to_string())
    out.write_string(",\"producers\":[")
    for i, field in producer_fields {
      if i > 0 {
        out.write_string(",")
      }
      out.write_string("{\"field\":")
      out.write_string(json_string(field.name))
      out.write_string(",\"values\":[")
      for j, entry in field.values {
        if j > 0 {
          out.write_string(",")
        }
        out.write_string("[\"")
        out.write_string(json_escape(entry.0))
        out.write_string("\",\"")
        out.write_string(json_escape(entry.1))
        out.write_string("\"]")
      }
      out.write_string("]}")
    }
    out.write_string("]}")
    return out.to_string()
  }
  let out = StringBuilder()
  out.write_string("custom sections: " + names.length().to_string() + "\n")
  for view in views {
    out.write_string("  " + view.name + "\n")
  }
  let subject = if kind.is_component() { "component" } else { "module" }
  match module_name {
    Some(value) => out.write_string(subject + " name: " + value + "\n")
    None => out.write_string(subject + " name: (none)\n")
  }
  if !kind.is_component() {
    out.write_string("function names: " + function_count.to_string() + "\n")
  }
  if producer_fields.is_empty() {
    out.write_string("producers: (none)\n")
  } else {
    out.write_string("producers:\n")
    for field in producer_fields {
      out.write_string("  " + field.name + ":\n")
      for entry in field.values {
        out.write_string("    " + entry.0 + " " + entry.1 + "\n")
      }
    }
  }
  out.to_string()
}

///|
fn json_string(value : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  out.write_string(json_escape(value))
  out.write_char('"')
  out.to_string()
}

///|
fn json_escape(value : String) -> String {
  let out = StringBuilder()
  for ch in value {
    match ch {
      '"' => {
        out.write_char('\\')
        out.write_char('"')
      }
      '\\' => {
        out.write_char('\\')
        out.write_char('\\')
      }
      '\n' => {
        out.write_char('\\')
        out.write_char('n')
      }
      '\r' => {
        out.write_char('\\')
        out.write_char('r')
      }
      '\t' => {
        out.write_char('\\')
        out.write_char('t')
      }
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// 指令的短形式：保留助记符与简单立即数，过长的嵌套块只显示助记符。
fn concise_instruction(text : String) -> String {
  if text.length() <= 48 {
    return text
  }
  match text.find("(") {
    Some(index) if index > 0 =>
      match text.get_view(start=0, end=index) {
        Some(view) => view.to_owned() + "(...)"
        None => text
      }
    _ => text
  }
}
