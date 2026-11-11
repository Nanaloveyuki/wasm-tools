///|
fn function_entry(name : String, params : Array[String]) -> Entry {
  {
    import_module: None,
    name,
    kind: ExternalKind::Function,
    type_: ExternalType::Function(params, []),
  }
}

///|
test "snapshot JSON roundtrips with deterministic ordering" {
  let snapshot = Snapshot::new(
    [
      {
        import_module: Some("host"),
        name: "log",
        kind: ExternalKind::Function,
        type_: ExternalType::Function(["i32"], []),
      },
    ],
    [function_entry("run \"main\"", ["i32", "i64"])],
  )
  let encoded = snapshot_json(snapshot)
  let decoded = parse_snapshot(encoded) catch { error => fail(error.message()) }
  inspect(snapshot_json(decoded) == encoded, content="true")
  inspect(decoded.imports[0].import_module == Some("host"), content="true")
}

///|
test "provided direction treats removed exports as breaking" {
  let baseline = Snapshot::new([], [function_entry("run", ["i32"])])
  let candidate = Snapshot::new([], [])
  let report = compare_snapshots(baseline, candidate, Direction::Provided)
  inspect(report.reports[0].status == Status::Breaking, content="true")
  inspect(report_text(report).contains("export run"), content="true")
}

///|
test "required direction treats removed and added imports by consumer need" {
  let import_entry = {
    import_module: Some("host"),
    name: "clock",
    kind: ExternalKind::Function,
    type_: ExternalType::Function([], ["i64"]),
  }
  let baseline = Snapshot::new([import_entry], [])
  let candidate = Snapshot::new([], [])
  let removed = compare_snapshots(baseline, candidate, Direction::Required)
  inspect(removed.reports[0].status == Status::Compatible, content="true")

  let added = compare_snapshots(candidate, baseline, Direction::Required)
  inspect(added.reports[0].status == Status::Breaking, content="true")
}

///|
test "both direction returns separate provider and requirement results" {
  let baseline = Snapshot::new(
    [
      {
        import_module: Some("host"),
        name: "clock",
        kind: ExternalKind::Function,
        type_: ExternalType::Function([], ["i64"]),
      },
    ],
    [function_entry("run", ["i32"])],
  )
  let candidate = Snapshot::new([], [])
  let report = compare_snapshots(baseline, candidate, Direction::Both)
  inspect(report.reports.length() == 2, content="true")
  inspect(report.reports[0].direction == Direction::Provided, content="true")
  inspect(report.reports[0].status == Status::Breaking, content="true")
  inspect(report.reports[1].direction == Direction::Required, content="true")
  inspect(report.reports[1].status == Status::Compatible, content="true")
}

///|
test "unsupported and duplicate entries fail closed as unknown" {
  let unsupported = Snapshot::new([], [
    {
      import_module: None,
      name: "typed",
      kind: ExternalKind::Function,
      type_: ExternalType::Unsupported("typed reference"),
    },
  ])
  let unsupported_report = compare_snapshots(
    unsupported,
    unsupported,
    Direction::Provided,
  )
  inspect(
    unsupported_report.reports[0].status == Status::Unknown,
    content="true",
  )

  let duplicate = function_entry("run", ["i32"])
  let duplicates = Snapshot::new([], [duplicate, duplicate])
  let duplicate_report = compare_snapshots(
    duplicates,
    duplicates,
    Direction::Provided,
  )
  inspect(duplicate_report.reports[0].status == Status::Unknown, content="true")
}

///|
test "snapshot parser rejects unsupported schema versions" {
  let parsed = parse_snapshot(
    "{\"format_version\":2,\"imports\":[],\"exports\":[],\"diagnostics\":[]}",
  ) catch {
    _ => return
  }
  ignore(parsed)
  fail("unsupported snapshot version was accepted")
}

///|
fn reverse_entries(entries : Array[Entry]) -> Array[Entry] {
  let reversed : Array[Entry] = []
  for i in 0..<entries.length() {
    reversed.push(entries[entries.length() - i - 1])
  }
  reversed
}

///|
test "law: Core ABI snapshot and comparison ignore declaration order" {
  @quickcheck.check(
    (values : Array[Bool]) => {
      let entries : Array[Entry] = []
      for i, value in values {
        let value_type = if value { "i32" } else { "i64" }
        entries.push(function_entry("export-" + i.to_string(), [value_type]))
      }
      let baseline_entries = entries.copy()
      baseline_entries.push(function_entry("changed", ["i32"]))
      let baseline : Snapshot = {
        format_version: SNAPSHOT_FORMAT_VERSION,
        imports: [],
        exports: baseline_entries,
        diagnostics: [],
      }
      let changed_entries = entries.copy()
      changed_entries.push(function_entry("changed", ["i64"]))
      let reordered : Snapshot = {
        format_version: SNAPSHOT_FORMAT_VERSION,
        imports: [],
        exports: reverse_entries(changed_entries),
        diagnostics: [],
      }
      let changed : Snapshot = {
        format_version: SNAPSHOT_FORMAT_VERSION,
        imports: [],
        exports: changed_entries,
        diagnostics: [],
      }
      let original_report = compare_snapshots(
        baseline,
        changed,
        Direction::Provided,
      )
      let reordered_report = compare_snapshots(
        baseline,
        reordered,
        Direction::Provided,
      )
      snapshot_json(changed) == snapshot_json(reordered) &&
      original_report.reports[0].status == Status::Breaking &&
      original_report == reordered_report
    },
    count=200,
    max_size=32,
    seed=20261111,
  )
}
