///|
test "contract extraction resolves imports and exported index spaces" {
  let wat =
    #|(module
    #|  (type $unary (func (param i32) (result i32)))
    #|  (import "host" "call" (func $call (type $unary)))
    #|  (import "host" "memory" (memory 1 2))
    #|  (import "host" "table" (table 2 8 funcref))
    #|  (import "host" "counter" (global i64))
    #|  (func $local (type $unary) (param i32) (result i32) local.get 0)
    #|  (export "run" (func $local))
    #|  (export "memory" (memory 0))
    #|  (export "table" (table 0))
    #|  (export "counter" (global 0)))
  let bytes = wat_to_core(wat) catch {
    _ => fail("failed to build test module")
  }
  let snapshot = contract_snapshot(bytes) catch {
    _ => fail("failed to extract contract")
  }
  inspect(snapshot.imports.length() == 4, content="true")
  inspect(snapshot.exports.length() == 4, content="true")

  let mut found_import_function = false
  for entry in snapshot.imports {
    if entry.name == "call" {
      found_import_function = entry.type_ ==
        @contract.ExternalType::Function(["i32"], ["i32"])
    }
  }
  inspect(found_import_function, content="true")

  let mut found_exported_function = false
  for entry in snapshot.exports {
    if entry.name == "run" {
      found_exported_function = entry.type_ ==
        @contract.ExternalType::Function(["i32"], ["i32"])
    }
  }
  inspect(found_exported_function, content="true")
}

///|
test "contract extraction marks typed GC signatures unsupported" {
  let wat = "(module (type $s (struct)) (func (export \"make\") (result (ref null $s)) ref.null $s))"
  let bytes = wat_to_core(wat) catch { _ => fail("failed to build GC module") }
  let snapshot = contract_snapshot(bytes) catch {
    _ => fail("failed to extract GC contract")
  }
  let exported = snapshot.exports[0]
  inspect(
    exported.type_ is @contract.ExternalType::Unsupported(_),
    content="true",
  )
}
