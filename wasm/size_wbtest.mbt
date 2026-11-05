///|
test "section totals plus header equal the file size" {
  let bytes = wat_to_core(
    "(module (func (export \"f\") (result i32) i32.const 1))",
  ) catch {
    _ => fail("parse failed")
  }
  let report = size_report(bytes, "test.wasm") catch { _ => fail("size failed") }
  let mut sum = report.header
  for section in report.sections {
    sum = sum + section.total
  }
  inspect(sum == bytes.length(), content="true")
  inspect(report.functions.length(), content="1")
  inspect(report.functions[0].bytes > 0, content="true")
  inspect(report.functions[0].index, content="0")
}

///|
test "component size reports sections without functions" {
  let bytes = @component_text.parse_component_wat(
    "(component (core module $m (func)) (core instance (instantiate $m)))",
  ) catch {
    _ => fail("component parse failed")
  }
  let report = size_report(bytes, "test.wasm") catch { _ => fail("size failed") }
  inspect(report.functions.length(), content="0")
  inspect(report.sections.length() > 0, content="true")
}
