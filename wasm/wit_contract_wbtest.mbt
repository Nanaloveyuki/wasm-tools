///|
fn build_test_wit_snapshot(source : String) -> @contract.WitSnapshot {
  try! wit_world_snapshot(@utf8.encode(source), "cli")
}

///|
fn alias_chain_source(
  terminal : String,
  length : Int32,
  shortcuts : Array[Bool],
) -> String {
  let source = StringBuilder()
  source.write_string("package demo:aliases; interface api {")
  for i in 0..<length {
    let target = if shortcuts.get(i).unwrap_or(false) {
      terminal
    } else {
      "t\{i + 1}"
    }
    source.write_string("type t\{i} = " + target + ";")
  }
  source.write_string("type t\{length} = " + terminal + ";")
  source.write_string("read: func(value: t0);}")
  source.write_string("world cli { import api; }")
  source.to_string()
}

///|
test "WIT adapter ignores package versions and source formatting" {
  let baseline = wit_world_snapshot(
    @utf8.encode(
      (
        #|package demo:calc@1.0.0;
        #|
        #|interface api {
        #|  record point { x: u32, y: u32 }
        #|  add: func(value: point) -> point;
        #|}
        #|world cli {
        #|  import api;
        #|  export run: func();
        #|}
        #|
      ),
    ),
    "cli",
  ) catch {
    error => fail(error.message())
  }
  let candidate = wit_world_snapshot(
    @utf8.encode(
      (
        #|package demo:calc@1.2.0;
        #|world cli { export run: func(); import api; }
        #|interface api { add: func(value: point) -> point; record point { x: u32, y: u32 } }
      ),
    ),
    "cli",
  ) catch {
    error => fail(error.message())
  }
  inspect(baseline.namespace_name == candidate.namespace_name, content="true")
  inspect(baseline.package_version == Some("1.0.0"), content="true")
  inspect(candidate.package_version == Some("1.2.0"), content="true")
  inspect(baseline.imports[0].name == candidate.imports[0].name, content="true")
  inspect(
    baseline.imports[0].signature == candidate.imports[0].signature,
    content="true",
  )
  inspect(
    baseline.exports[0].signature == candidate.exports[0].signature,
    content="true",
  )
}

///|
test "WIT adapter captures interface field changes" {
  let baseline = build_test_wit_snapshot(
    (
      #|package demo:calc@1.0.0;
      #|interface api { record point { x: u32, y: u32 } add: func(value: point) -> point; }
      #|world cli { import api; }
    ),
  )
  let candidate = build_test_wit_snapshot(
    (
      #|package demo:calc@2.0.0;
      #|interface api { record point { x: u32, z: u32 } add: func(value: point) -> point; }
      #|world cli { import api; }
    ),
  )
  let report = @contract.compare_wit_snapshots(baseline, candidate)
  inspect(report.status == @contract.Breaking, content="true")
}

///|
test "WIT adapter compares long verified alias chains structurally" {
  let baseline = build_test_wit_snapshot(alias_chain_source("u32", 1024, []))
  let shortcuts = Array::make(1024, true)
  let same = build_test_wit_snapshot(alias_chain_source("u32", 1024, shortcuts))
  let changed = build_test_wit_snapshot(
    alias_chain_source("u64", 1024, shortcuts),
  )
  inspect(baseline.imports[0].signature.has_prefix("unknown:"), content="false")
  inspect(
    baseline.imports[0].signature == same.imports[0].signature,
    content="true",
  )
  inspect(
    baseline.imports[0].signature != changed.imports[0].signature,
    content="true",
  )
  inspect(
    @contract.compare_wit_snapshots(baseline, same).status ==
    @contract.Compatible,
    content="true",
  )
  inspect(
    @contract.compare_wit_snapshots(baseline, changed).status ==
    @contract.Breaking,
    content="true",
  )
}

///|
test "law: WIT alias shortcutting preserves the resolved type" {
  @quickcheck.check(
    (shortcuts : Array[Bool]) => {
      let length = 257 + shortcuts.length()
      let baseline = build_test_wit_snapshot(
        alias_chain_source("u32", length, []),
      )
      let candidate = build_test_wit_snapshot(
        alias_chain_source("u32", length, shortcuts),
      )
      !baseline.imports[0].signature.has_prefix("unknown:") &&
      !candidate.imports[0].signature.has_prefix("unknown:") &&
      baseline.imports[0].signature == candidate.imports[0].signature &&
      @contract.compare_wit_snapshots(baseline, candidate).status ==
      @contract.Compatible
    },
    count=100,
    max_size=32,
    seed=20261113,
  )
}

///|
test "WIT adapter stabilizes resource identities across source versions" {
  let baseline = wit_world_snapshot(
    @utf8.encode(
      (
        #|package demo:store@1.0.0;
        #|interface storage {
        #|  resource item {
        #|    constructor();
        #|    read: func() -> string;
        #|  }
        #|}
        #|world cli { import storage; }
      ),
    ),
    "cli",
  ) catch {
    error => fail(error.message())
  }
  let candidate = wit_world_snapshot(
    @utf8.encode(
      (
        #|package demo:store@2.0.0;
        #|world cli { import storage; }
        #|interface storage { resource item { read: func() -> string; constructor(); } }
      ),
    ),
    "cli",
  ) catch {
    error => fail(error.message())
  }
  inspect(
    @contract.compare_wit_snapshots(baseline, candidate).status ==
    @contract.Compatible,
    content="true",
  )
}

///|
test "WIT adapter includes unstable features but marks them unknown" {
  let source =
    #|package demo:calc@1.0.0;
    #|interface api { @unstable(feature = preview) hidden: func(); }
    #|world cli { import api; }
  let snapshot = build_test_wit_snapshot(source)
  inspect(snapshot.imports[0].signature.has_prefix("unknown:"), content="true")
  let world_item = build_test_wit_snapshot(
    (
      #|package demo:calc@1.0.0;
      #|interface api { ping: func(); }
      #|world cli { @unstable(feature = preview) import api; }
    ),
  )
  inspect(
    world_item.imports[0].signature.has_prefix("unknown:"),
    content="true",
  )
}

///|
test "WIT adapter requires the requested world" {
  let source = "package demo:calc; world other {}"
  let accepted = try {
    ignore(wit_world_snapshot(@utf8.encode(source), "cli"))
    true
  } catch {
    _ => false
  }
  inspect(accepted, content="false")
}

///|
test "WIT adapter rejects a feature-gated world" {
  let source = "package demo:calc; @unstable(feature=preview) world cli {}"
  let accepted = try {
    ignore(wit_world_snapshot(@utf8.encode(source), "cli"))
    true
  } catch {
    _ => false
  }
  inspect(accepted, content="false")
}
