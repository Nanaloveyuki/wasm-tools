///|
test "value options do not swallow the input file" {
  let options = parse_options(
    ["--keep", "producers", "app.wasm", "-o", "out.wasm"],
    value_options=["--keep"],
  ) catch {
    _ => fail("parse_options failed")
  }
  inspect(options.input.unwrap_or(""), content="app.wasm")
  inspect(options.output.unwrap_or(""), content="out.wasm")
  inspect(options.extra.length(), content="2")
}

///|
test "unknown options are preserved for the command" {
  let options = parse_options(["--instructions", "app.wasm"]) catch {
    _ => fail("parse_options failed")
  }
  inspect(options.input.unwrap_or(""), content="app.wasm")
  inspect(options.extra[0], content="--instructions")
}

///|
test "json is rejected when the command does not allow it" {
  let mut rejected = false
  try {
    let _ = parse_options(["--json", "app.wasm"])
  } catch {
    CliError::Usage(_) => rejected = true
    _ => fail("unexpected error")
  }
  inspect(rejected, content="true")
}
