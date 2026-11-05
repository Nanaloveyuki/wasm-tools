///|
test "detect_kind distinguishes core modules from components" {
  let core = @wasm.wat_to_core("(module (func))") catch {
    _ => fail("parse failed")
  }
  match @wasm.detect_kind(core) {
    CoreModule => ()
    Component => fail("expected a core module")
  }
}

///|
test "scan_sections chains offsets without gaps" {
  let bytes = @wasm.wat_to_core(
    "(module (func (export \"f\") (result i32) i32.const 1))",
  ) catch {
    _ => fail("parse failed")
  }
  let sections = @wasm.scan_sections(bytes) catch { _ => fail("scan failed") }
  let mut expected_start = 8
  for section in sections {
    if section.start != expected_start {
      fail(
        "section at " +
        section.start.to_string() +
        " should start at " +
        expected_start.to_string(),
      )
    }
    expected_start = section.payload + section.size
  }
  inspect(expected_start == bytes.length(), content="true")
}

///|
test "strip removes only custom sections" {
  let bytes = @wasm.wat_to_core(
    "(module (func (export \"f\") (result i32) i32.const 1))",
  ) catch {
    _ => fail("parse failed")
  }
  let sections = @wasm.scan_sections(bytes) catch { _ => fail("scan failed") }
  let stripped = @wasm.strip_custom_sections(bytes, sections, fn(_name) { true })
  let after = @wasm.scan_sections(stripped) catch { _ => fail("rescan failed") }
  for section in after {
    if section.id == 0 {
      fail("custom section survived strip")
    }
  }
  @wasm.validate_core(stripped) catch {
    _ => fail("stripped module does not validate")
  }
}

///|
test "truncated input is rejected rather than panicking" {
  let bad = Bytes::from_array([
    b'\x00', b'a', b's', b'm', b'\x01', b'\x00', b'\x00', b'\x00', b'\x01', b'\x7f',
  ])
  let mut rejected = false
  try {
    let _ = @wasm.scan_sections(bad)
  } catch {
    @cli.CliError::Invalid(_) => rejected = true
    _ => fail("wrong error kind")
  }
  inspect(rejected, content="true")
}
