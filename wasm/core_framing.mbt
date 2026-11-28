///|
fn code_layouts(
  data : Bytes,
  section : Section,
) -> Array[FunctionLayout] raise @cli.CliError {
  let cursor = Ref(section.payload)
  let end = section.payload + section.size
  let count = read_leb_until(data, cursor, end)
  let layouts : Array[FunctionLayout] = []
  for _ in 0..<count {
    let size = read_leb_until(data, cursor, end)
    let start = cursor.val
    guard size >= 2 && size <= end - start else {
      raise @cli.CliError::Invalid(
        "function body size is outside the code section",
      )
    }
    layouts.push({ start, size, })
    cursor.val = start + size
  }
  require_payload_end(cursor, end)
  layouts
}

///|
fn find_code_layouts(
  data : Bytes,
  sections : Array[Section],
) -> Array[FunctionLayout] raise @cli.CliError {
  for section in sections {
    if section.id == 10 {
      return code_layouts(data, section)
    }
  }
  []
}

///|
fn parse_core_framed(
  data : Bytes,
  sections : Array[Section],
) -> @core_types.Module raise @cli.CliError {
  for section in sections {
    if section.id == 10 {
      let layouts = code_layouts(data, section)
      if !layouts.is_empty() {
        return parse_framed_code(data, section, layouts)
      }
    }
  }
  @core_parser.parse_module(data) catch {
    e => raise @cli.CliError::Invalid("parse: " + e.to_string())
  }
}

///|
// wasm_core 0.19 does not check function body sizes. Insert a nop just before
// each declared end and require the parser to see it as the last top-level
// instruction of that function at exactly the inserted position.
fn parse_framed_code(
  data : Bytes,
  section : Section,
  layouts : Array[FunctionLayout],
) -> @core_types.Module raise @cli.CliError {
  guard data.length().to_int64() + layouts.length().to_int64() * 2L + 5L <=
    2147483647L else {
    raise @cli.CliError::Invalid(
      "code section is too large to check function framing",
    )
  }
  let code = @buffer.Buffer(capacity=section.size + layouts.length())
  let markers : Array[Int32] = []
  write_u32_leb(code, layouts.length())
  for layout in layouts {
    let last = layout.start + layout.size - 1
    guard data[last] == b'\x0b' else {
      raise @cli.CliError::Invalid(
        "function body must end at its declared size",
      )
    }
    write_u32_leb(code, layout.size + 1)
    code.write_bytesview(data.exact_view(start=layout.start, end=last))
    markers.push(code.length())
    code.write_byte(b'\x01')
    code.write_byte(b'\x0b')
  }
  let framed = @buffer.Buffer()
  framed.write_bytesview(data.exact_view(end=section.start))
  framed.write_byte(b'\x0a')
  write_u32_leb(framed, code.length())
  let code_start = framed.length()
  framed.write_bytesview(code.to_bytes()[:])
  framed.write_bytesview(data.exact_view(start=section.payload + section.size))
  let (parsed, sources) = @core_parser.parse_module_with_sources(
    framed.to_bytes(),
  ) catch {
    e => raise @cli.CliError::Invalid("parse: " + e.to_string())
  }
  guard parsed.codes.length() == markers.length() &&
    sources.length() == markers.length() else {
    raise @cli.CliError::Invalid(
      "parsed code count does not match the code section",
    )
  }
  for index, marker in markers {
    let instructions = parsed.codes[index].body
    guard instructions.last() is Some(Nop) &&
      sources[index].last() is Some(source) &&
      source.byte_offset == code_start + marker else {
      raise @cli.CliError::Invalid(
        "function body does not match its declared size",
      )
    }
    parsed.codes[index] = {
      ..parsed.codes[index],
      body: ReadOnlyArray::from_array(
        instructions[:instructions.length() - 1].to_owned(),
      ),
    }
  }
  parsed
}

///|
fn write_u32_leb(out : @buffer.Buffer, value : Int32) -> Unit {
  for remaining = value; ; remaining = remaining >> 7 {
    if remaining < 128 {
      out.write_byte(remaining.to_byte())
      break
    }
    out.write_byte(((remaining & 0x7f) | 0x80).to_byte())
  }
}
