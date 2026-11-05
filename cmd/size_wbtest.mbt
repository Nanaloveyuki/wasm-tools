///|
test "budget accepts common units" {
  inspect(parse_budget([]) is None, content="true")
  inspect(parse_budget(["1"]) .unwrap_or(-1), content="1")
  inspect(parse_budget(["1KB"]).unwrap_or(-1), content="1024")
  inspect(parse_budget(["2MB"]).unwrap_or(-1), content="2097152")
}
