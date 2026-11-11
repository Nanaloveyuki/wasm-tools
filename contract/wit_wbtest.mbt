///|
fn wit_test_entry(name : String, kind : String, signature : String) -> WitEntry {
  { name, kind, signature, }
}

///|
fn wit_test_snapshot(
  version : String?,
  imports : Array[WitEntry],
  exports : Array[WitEntry],
) -> WitSnapshot {
  WitSnapshot::new("demo", "calc", version, "cli", imports, exports)
}

///|
test "WIT snapshots roundtrip with deterministic item ordering" {
  let snapshot = wit_test_snapshot(
    Some("1.0.0"),
    [
      wit_test_entry("z", "function", "fn[]->unit"),
      wit_test_entry("a", "interface", "interface{}"),
    ],
    [],
  )
  let encoded = wit_snapshot_json(snapshot)
  let decoded = parse_wit_snapshot(encoded) catch {
    error => fail(error.message())
  }
  inspect(wit_snapshot_json(decoded) == encoded, content="true")
  inspect(decoded.imports[0].name, content="a")
}

///|
test "WIT version changes ignore source version and declaration order" {
  let baseline = wit_test_snapshot(Some("1.0.0"), [], [])
  let candidate = wit_test_snapshot(Some("1.2.3"), [], [])
  let report = compare_wit_snapshots(baseline, candidate)
  inspect(report.status == Compatible, content="true")
  inspect(report.baseline_version == Some("1.0.0"), content="true")
  inspect(report.candidate_version == Some("1.2.3"), content="true")
}

///|
test "WIT SemVer direction allows new imports and removed exports" {
  let baseline = wit_test_snapshot(
    Some("1.0.0"),
    [wit_test_entry("host:old", "function", "fn[]->unit")],
    [wit_test_entry("run", "function", "fn[]->unit")],
  )
  let candidate = wit_test_snapshot(
    Some("1.1.0"),
    [
      wit_test_entry("host:old", "function", "fn[]->unit"),
      wit_test_entry("host:new", "function", "fn[]->unit"),
    ],
    [],
  )
  let report = compare_wit_snapshots(baseline, candidate)
  inspect(report.status == Compatible, content="true")
}

///|
test "WIT SemVer direction rejects removed imports and added exports" {
  let baseline = wit_test_snapshot(
    Some("1.0.0"),
    [wit_test_entry("host:old", "function", "fn[]->unit")],
    [],
  )
  let candidate = wit_test_snapshot(Some("1.1.0"), [], [
    wit_test_entry("run", "function", "fn[]->unit"),
  ])
  let report = compare_wit_snapshots(baseline, candidate)
  inspect(report.status == Breaking, content="true")
}

///|
test "WIT type changes break and unknown signatures fail closed" {
  let baseline = wit_test_snapshot(Some("1.0.0"), [], [
    wit_test_entry("run", "function", "fn[u32]->u32"),
  ])
  let changed = wit_test_snapshot(Some("1.1.0"), [], [
    wit_test_entry("run", "function", "fn[u64]->u64"),
  ])
  let unknown = wit_test_snapshot(Some("1.1.0"), [], [
    wit_test_entry("run", "function", "unknown:unmodeled type"),
  ])
  inspect(
    compare_wit_snapshots(baseline, changed).status == Breaking,
    content="true",
  )
  inspect(
    compare_wit_snapshots(baseline, unknown).status == Unknown,
    content="true",
  )
}

///|
test "WIT snapshots from another package or world are unknown" {
  let baseline = wit_test_snapshot(None, [], [
    wit_test_entry("run", "function", "fn[]->unit"),
  ])
  let other_package = WitSnapshot::new("other", "calc", None, "cli", [], [])
  let other_world = WitSnapshot::new("demo", "calc", None, "component", [], [])
  let package_report = compare_wit_snapshots(baseline, other_package)
  let world_report = compare_wit_snapshots(baseline, other_world)
  inspect(package_report.status == Unknown, content="true")
  inspect(package_report.changes.length() == 1, content="true")
  inspect(world_report.status == Unknown, content="true")
  inspect(world_report.changes.length() == 1, content="true")
}

///|
fn reverse_wit_entries(entries : Array[WitEntry]) -> Array[WitEntry] {
  let reversed : Array[WitEntry] = []
  for i in 0..<entries.length() {
    reversed.push(entries[entries.length() - i - 1])
  }
  reversed
}

///|
test "law: WIT comparison ignores declaration order and package version" {
  @quickcheck.check(
    (values : Array[Bool]) => {
      let entries : Array[WitEntry] = []
      for i, value in values {
        let value_type = if value { "u32" } else { "u64" }
        entries.push(
          wit_test_entry(
            "item-" + i.to_string(),
            "function",
            "fn[" + value_type + "]->unit",
          ),
        )
      }
      let baseline_entries = entries.copy()
      baseline_entries.push(
        wit_test_entry("changed", "function", "fn[i32]->unit"),
      )
      let changed_entries = entries.copy()
      changed_entries.push(
        wit_test_entry("changed", "function", "fn[i64]->unit"),
      )
      let baseline : WitSnapshot = {
        format_version: WIT_SNAPSHOT_FORMAT_VERSION,
        namespace_name: "demo",
        package_name: "calc",
        package_version: Some("1.0.0"),
        world: "cli",
        imports: baseline_entries,
        exports: [],
      }
      let candidate : WitSnapshot = {
        format_version: WIT_SNAPSHOT_FORMAT_VERSION,
        namespace_name: "demo",
        package_name: "calc",
        package_version: Some("2.0.0"),
        world: "cli",
        imports: changed_entries,
        exports: [],
      }
      let reordered : WitSnapshot = {
        ..candidate,
        imports: reverse_wit_entries(changed_entries),
      }
      let report = compare_wit_snapshots(baseline, reordered)
      let same_version = compare_wit_snapshots(
        { ..baseline, package_version: None, },
        { ..reordered, package_version: None, },
      )
      let stable_json = wit_snapshot_json({
          ..candidate,
          package_version: None,
        }) ==
        wit_snapshot_json({ ..reordered, package_version: None, })
      stable_json &&
      report.status == Status::Breaking &&
      report.status == same_version.status &&
      report.changes == same_version.changes
    },
    count=200,
    max_size=32,
    seed=20261112,
  )
}
