///|
test "symbolize maps an absolute offset to a named function" {
  let bytes = wat_to_core(
    "(module (func $add (result i32) i32.const 1) (export \"add\" (func $add)))",
  ) catch {
    _ => fail("parse failed")
  }
  let layout = function_layout(
    bytes,
    scan_sections(bytes) catch {
      _ => fail("scan failed")
    },
  )
  let entry = match layout.get(0) {
    Some(entry) => entry
    None => fail("function 0 not laid out")
  }
  let address = "wasm-function[0]:0x" + hex(entry.start + 1)
  let symbol = symbolize(bytes, address) catch { _ => fail("symbolize failed") }
  inspect(symbol.name.unwrap_or(""), content="add")
  inspect(symbol.function_offset.unwrap_or(-1), content="1")
  inspect(symbol.address, content=(entry.start + 1).to_string())
}

///|
test "symbolize rejects malformed addresses" {
  let bytes = wat_to_core("(module)") catch { _ => fail("parse failed") }
  let mut rejected = false
  try {
    let _ = symbolize(bytes, "not-an-address")
  } catch {
    @cli.CliError::Usage(_) => rejected = true
    _ => fail("unexpected error kind")
  }
  inspect(rejected, content="true")
}
