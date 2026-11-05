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

///|
test "size_diff classifies added, removed and changed functions" {
  let base = size_report(
    wat_to_core("(module (func $a (result i32) i32.const 1) (export \"a\" (func $a)))") catch {
      _ => fail("parse failed")
    },
    "base.wasm",
  ) catch {
    _ => fail("size failed")
  }
  let current = size_report(
    wat_to_core(
      "(module (func $a (result i32) i32.const 1 i32.const 2 i32.add) (export \"a\" (func $a)) (func $b (result i32) i32.const 3) (export \"b\" (func $b)))",
    ) catch {
      _ => fail("parse failed")
    },
    "current.wasm",
  ) catch {
    _ => fail("size failed")
  }
  let diff = size_diff(current, base)
  let mut added = 0
  let mut changed = 0
  for change in diff.changes {
    if change.status == "added" {
      added = added + 1
    } else if change.status == "changed" {
      changed = changed + 1
    }
  }
  inspect(added, content="1")
  inspect(changed, content="1")
  inspect(diff.after_total > diff.before_total, content="true")
}
