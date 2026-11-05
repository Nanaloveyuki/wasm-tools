///|
/// 同包测试：直接调用本地函数，不经 `@wasm.` 前缀。
test "compose_packages collects every new package once" {
  let script =
    #|package example:app;
    #|let a = new example:one {};
    #|let b = new example:two { x: a.y };
    #|let c = new example:one {};
  let names = @wasm.compose_packages(script) catch { _ => fail("parse failed") }
  inspect(names.length(), content="2")
  inspect(names[0], content="example:one")
  inspect(names[1], content="example:two")
}

///|
test "compose_packages rejects malformed scripts" {
  let mut rejected = false
  try {
    let _ = @wasm.compose_packages("let x = ;")
  } catch {
    @cli.CliError::Invalid(_) => rejected = true
    _ => fail("unexpected error kind")
  }
  inspect(rejected, content="true")
}
