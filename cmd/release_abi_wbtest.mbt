///|
fn release_abi_test_report(
  schema : Int32,
  outcome : String,
  sha256 : String,
  resource_classification : String?,
) -> Json {
  let resources = match resource_classification {
    Some(classification) =>
      "\"resources\":{\"status\":\"evaluated\",\"classification\":" +
      Json::string(classification).stringify() +
      ",\"changes\":[]},"
    None => ""
  }
  let text = "{\"schemaVersion\":" +
    schema.to_string() +
    ",\"outcome\":" +
    Json::string(outcome).stringify() +
    ",\"artifact\":{\"status\":\"valid\",\"sha256\":" +
    Json::string(sha256).stringify() +
    ",\"diagnostics\":[]},\"baseline\":{\"status\":\"valid\",\"artifactSha256\":\"old\",\"abiSha256\":\"old\",\"diagnostic\":null},\"provenance\":{\"artifactMatchesBaseline\":false,\"abiMatchesBaseline\":false},\"compatibility\":{\"status\":\"evaluated\",\"classification\":\"compatible\",\"changes\":[]}," +
    resources +
    "\"contract\":{\"status\":\"notProvided\",\"diagnostic\":null},\"generator\":{\"status\":\"representable\",\"diagnostics\":[]}}"
  @json.parse(text) catch {
    _ => Json::null()
  }
}

///|
test "release ABI accepts a compatible schema v1 report" {
  let report = release_abi_test_report(1, "compatible", "abc", None)
  inspect(validate_release_abi_report(report, "abc", 0) is None, content="true")
  inspect(release_abi_report_is_compatible(report), content="true")
}

///|
test "release ABI validates schema v2 resource section" {
  let report = release_abi_test_report(
    2,
    "compatible",
    "abc",
    Some("compatible"),
  )
  inspect(validate_release_abi_report(report, "abc", 0) is None, content="true")
  inspect(release_abi_report_is_compatible(report), content="true")
}

///|
test "release ABI rejects breaking schema v2 resources" {
  let report = release_abi_test_report(2, "compatible", "abc", Some("breaking"))
  inspect(validate_release_abi_report(report, "abc", 0) is None, content="true")
  inspect(release_abi_report_is_compatible(report), content="false")
}

///|
test "release ABI rejects an unsupported schema independently" {
  let report = release_abi_test_report(3, "compatible", "abc", None)
  inspect(
    validate_release_abi_report(report, "abc", 0) is Some(_),
    content="true",
  )
}

///|
test "release ABI rejects an unknown outcome independently" {
  let report = release_abi_test_report(1, "mystery", "abc", None)
  inspect(
    validate_release_abi_report(report, "abc", 0) is Some(_),
    content="true",
  )
}

///|
test "release ABI rejects a candidate hash mismatch independently" {
  let report = release_abi_test_report(1, "compatible", "wrong", None)
  inspect(
    validate_release_abi_report(report, "abc", 0) is Some(_),
    content="true",
  )
}

///|
test "release ABI rejects a breaking outcome with exit code zero" {
  let report = release_abi_test_report(1, "breaking", "abc", None)
  inspect(
    validate_release_abi_report(report, "abc", 0) is Some(_),
    content="true",
  )
  inspect(release_abi_report_is_compatible(report), content="false")
}
