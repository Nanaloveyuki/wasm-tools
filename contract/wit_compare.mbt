///|
pub fn compare_wit_snapshots(
  baseline : WitSnapshot,
  candidate : WitSnapshot,
) -> WitReport {
  let changes : Array[Change] = []
  let mut can_compare = true
  if baseline.format_version != WIT_SNAPSHOT_FORMAT_VERSION ||
    candidate.format_version != WIT_SNAPSHOT_FORMAT_VERSION {
    can_compare = false
    changes.push({
      key: "snapshot",
      status: Unknown,
      detail: "unsupported in-memory WIT snapshot format version",
    })
  }
  if baseline.namespace_name != candidate.namespace_name ||
    baseline.package_name != candidate.package_name {
    can_compare = false
    changes.push({
      key: "package",
      status: Unknown,
      detail: "WIT snapshots must describe the same namespace and package",
    })
  }
  if baseline.world != candidate.world {
    can_compare = false
    changes.push({
      key: "world",
      status: Unknown,
      detail: "WIT snapshots must select the same world",
    })
  }
  if can_compare {
    compare_wit_side(baseline.imports, candidate.imports, true, changes)
    compare_wit_side(baseline.exports, candidate.exports, false, changes)
  }
  {
    namespace_name: candidate.namespace_name,
    package_name: candidate.package_name,
    baseline_version: baseline.package_version,
    candidate_version: candidate.package_version,
    world: candidate.world,
    status: wit_overall_status(changes),
    changes,
  }
}

///|
fn compare_wit_side(
  old_entries : Array[WitEntry],
  new_entries : Array[WitEntry],
  imports : Bool,
  changes : Array[Change],
) -> Unit {
  let old_by_name = group_wit_entries(old_entries)
  let new_by_name = group_wit_entries(new_entries)
  let names : Array[String] = []
  for name in old_by_name.keys() {
    names.push(name)
  }
  for name in new_by_name.keys() {
    if !names.contains(name) {
      names.push(name)
    }
  }
  names.sort_by(fn(left, right) { left.lexical_compare(right) })
  for name in names {
    let old_group = old_by_name.get(name).unwrap_or([])
    let new_group = new_by_name.get(name).unwrap_or([])
    let label = (if imports { "import " } else { "export " }) + name
    if old_group.length() > 1 || new_group.length() > 1 {
      changes.push({
        key: label,
        status: Unknown,
        detail: "duplicate WIT world item identity cannot be compared safely",
      })
      continue
    }
    match (old_group.get(0), new_group.get(0)) {
      (Some(old_entry), Some(new_entry)) =>
        if old_entry.signature.has_prefix("unknown:") ||
          new_entry.signature.has_prefix("unknown:") {
          let detail = if old_entry.signature.has_prefix("unknown:") {
            old_entry.signature
          } else {
            new_entry.signature
          }
          changes.push({
            key: label,
            status: Unknown,
            detail: "WIT item cannot be compared safely: " +
            detail[8:].to_owned(),
          })
        } else if old_entry.kind != new_entry.kind ||
          old_entry.signature != new_entry.signature {
          changes.push({
            key: label,
            status: Breaking,
            detail: "WIT item kind or structural type changed",
          })
        }
      (Some(_), None) =>
        if imports {
          changes.push({
            key: label,
            status: Breaking,
            detail: "candidate removed a required import",
          })
        } else {
          changes.push({
            key: label,
            status: Compatible,
            detail: "candidate removed an export",
          })
        }
      (None, Some(_)) =>
        if imports {
          changes.push({
            key: label,
            status: Compatible,
            detail: "candidate added an import",
          })
        } else {
          changes.push({
            key: label,
            status: Breaking,
            detail: "candidate added an export",
          })
        }
      (None, None) => ()
    }
  }
}

///|
fn group_wit_entries(entries : Array[WitEntry]) -> Map[String, Array[WitEntry]] {
  let groups : Map[String, Array[WitEntry]] = Map([])
  for entry in entries {
    match groups.get(entry.name) {
      Some(group) => group.push(entry)
      None => groups[entry.name] = [entry]
    }
  }
  groups
}

///|
fn wit_overall_status(changes : Array[Change]) -> Status {
  let mut has_unknown = false
  for change in changes {
    match change.status {
      Breaking => return Breaking
      Unknown => has_unknown = true
      Compatible => ()
    }
  }
  if has_unknown {
    Unknown
  } else {
    Compatible
  }
}

///|
pub fn wit_report_text(report : WitReport) -> String {
  let out = StringBuilder()
  out.write_string(
    report.namespace_name +
    ":" +
    report.package_name +
    "/" +
    report.world +
    ": " +
    status_name(report.status) +
    "\n",
  )
  out.write_string(
    "  package versions: " +
    report.baseline_version.unwrap_or("(unversioned)") +
    " -> " +
    report.candidate_version.unwrap_or("(unversioned)") +
    "\n",
  )
  if report.changes.is_empty() {
    out.write_string("  no interface changes\n")
  } else {
    for change in report.changes {
      out.write_string(
        "  " +
        status_name(change.status) +
        "  " +
        change.key +
        ": " +
        change.detail +
        "\n",
      )
    }
  }
  out.to_string()
}

///|
pub fn wit_report_json(report : WitReport) -> String {
  let out = StringBuilder()
  out.write_string("{\"namespace\":")
  out.write_string(json_string(report.namespace_name))
  out.write_string(",\"package\":")
  out.write_string(json_string(report.package_name))
  out.write_string(",\"baseline_version\":")
  match report.baseline_version {
    Some(version) => out.write_string(json_string(version))
    None => out.write_string("null")
  }
  out.write_string(",\"candidate_version\":")
  match report.candidate_version {
    Some(version) => out.write_string(json_string(version))
    None => out.write_string("null")
  }
  out.write_string(",\"world\":")
  out.write_string(json_string(report.world))
  out.write_string(",\"status\":")
  out.write_string(json_string(status_name(report.status)))
  out.write_string(",\"changes\":[")
  for i, change in report.changes {
    if i > 0 {
      out.write_char(',')
    }
    out.write_string("{\"key\":")
    out.write_string(json_string(change.key))
    out.write_string(",\"status\":")
    out.write_string(json_string(status_name(change.status)))
    out.write_string(",\"detail\":")
    out.write_string(json_string(change.detail))
    out.write_char('}')
  }
  out.write_string("]}")
  out.to_string()
}
