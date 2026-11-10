///|
pub fn compare_snapshots(
  baseline : Snapshot,
  candidate : Snapshot,
  direction : Direction,
) -> Report {
  let reports : Array[DirectionReport] = []
  match direction {
    Provided => reports.push(compare_direction(baseline, candidate, Provided))
    Required => reports.push(compare_direction(baseline, candidate, Required))
    Both => {
      reports.push(compare_direction(baseline, candidate, Provided))
      reports.push(compare_direction(baseline, candidate, Required))
    }
  }
  { reports, }
}

///|
fn compare_direction(
  baseline : Snapshot,
  candidate : Snapshot,
  direction : Direction,
) -> DirectionReport {
  let old_entries = entries_for(baseline, direction)
  let new_entries = entries_for(candidate, direction)
  let old_by_key = group_entries(old_entries)
  let new_by_key = group_entries(new_entries)
  let keys : Array[String] = []
  for key in old_by_key.keys() {
    keys.push(key)
  }
  for key in new_by_key.keys() {
    if !contains(keys, key) {
      keys.push(key)
    }
  }
  keys.sort_by(fn(left, right) {
    if left < right {
      -1
    } else if left > right {
      1
    } else {
      0
    }
  })
  let changes : Array[Change] = []
  for key in keys {
    let old_group = old_by_key.get(key).unwrap_or([])
    let new_group = new_by_key.get(key).unwrap_or([])
    if old_group.length() > 1 || new_group.length() > 1 {
      let entry = if old_group.length() > 0 {
        old_group[0]
      } else {
        new_group[0]
      }
      changes.push({
        key: entry_label(entry, direction),
        status: Unknown,
        detail: "duplicate external identity cannot be compared safely",
      })
      continue
    }
    match (old_group.get(0), new_group.get(0)) {
      (None, None) => ()
      (Some(_), Some(_)) => {
        let old_entry = old_group[0]
        let new_entry = new_group[0]
        match (old_entry.type_, new_entry.type_) {
          (Unsupported(reason), _) | (_, Unsupported(reason)) =>
            changes.push({
              key: entry_label(new_entry, direction),
              status: Unknown,
              detail: "unsupported interface type: " + reason,
            })
          (old_type, new_type) =>
            if old_type != new_type {
              changes.push({
                key: entry_label(new_entry, direction),
                status: Breaking,
                detail: type_changed_detail(direction),
              })
            }
        }
      }
      (Some(entry), None) =>
        match entry.type_ {
          Unsupported(reason) =>
            changes.push({
              key: entry_label(entry, direction),
              status: Unknown,
              detail: "unsupported interface type: " + reason,
            })
          _ => {
            let status = match direction {
              Provided => Breaking
              Required => Compatible
              Both => Unknown
            }
            changes.push({
              key: entry_label(entry, direction),
              status,
              detail: missing_detail(direction),
            })
          }
        }
      (None, Some(entry)) =>
        match entry.type_ {
          Unsupported(reason) =>
            changes.push({
              key: entry_label(entry, direction),
              status: Unknown,
              detail: "unsupported interface type: " + reason,
            })
          _ => {
            let status = match direction {
              Provided => Compatible
              Required => Breaking
              Both => Unknown
            }
            changes.push({
              key: entry_label(entry, direction),
              status,
              detail: added_detail(direction),
            })
          }
        }
    }
  }
  append_diagnostics(changes, "baseline", baseline.diagnostics)
  append_diagnostics(changes, "candidate", candidate.diagnostics)
  if baseline.format_version != SNAPSHOT_FORMAT_VERSION ||
    candidate.format_version != SNAPSHOT_FORMAT_VERSION {
    changes.push({
      key: "snapshot",
      status: Unknown,
      detail: "unsupported in-memory snapshot format version",
    })
  }
  let status = overall_status(changes)
  { direction, status, changes, }
}

///|
fn entries_for(snapshot : Snapshot, direction : Direction) -> Array[Entry] {
  match direction {
    Provided => snapshot.exports
    Required => snapshot.imports
    Both => []
  }
}

///|
fn group_entries(entries : Array[Entry]) -> Map[String, Array[Entry]] {
  let groups : Map[String, Array[Entry]] = Map([])
  for entry in entries {
    let key = entry_key(entry)
    match groups.get(key) {
      Some(group) => group.push(entry)
      None => groups.set(key, [entry])
    }
  }
  groups
}

///|
fn contains(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
fn append_diagnostics(
  changes : Array[Change],
  side : String,
  diagnostics : Array[String],
) -> Unit {
  for diagnostic in diagnostics {
    changes.push({
      key: "snapshot",
      status: Unknown,
      detail: side + " snapshot: " + diagnostic,
    })
  }
}

///|
fn overall_status(changes : Array[Change]) -> Status {
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
fn missing_detail(direction : Direction) -> String {
  match direction {
    Provided => "previously provided export was removed"
    Required => "previously required import is no longer needed"
    Both => "external interface was removed"
  }
}

///|
fn added_detail(direction : Direction) -> String {
  match direction {
    Provided => "new export was added"
    Required => "new import requirement was added"
    Both => "external interface was added"
  }
}

///|
fn type_changed_detail(direction : Direction) -> String {
  match direction {
    Provided => "export type changed"
    Required => "import requirement type changed"
    Both => "external interface type changed"
  }
}

///|
fn entry_label(entry : Entry, direction : Direction) -> String {
  let role = match direction {
    Provided => "export"
    Required => "import"
    Both => "external"
  }
  let identity = match entry.import_module {
    Some(import_module) => import_module + "." + entry.name
    None => entry.name
  }
  role + " " + identity + " (" + kind_name(entry.kind) + ")"
}

///|
pub fn status_name(status : Status) -> String {
  match status {
    Compatible => "compatible"
    Unknown => "unknown"
    Breaking => "breaking"
  }
}

///|
pub fn direction_name(direction : Direction) -> String {
  match direction {
    Provided => "provided"
    Required => "required"
    Both => "both"
  }
}

///|
pub fn report_text(report : Report) -> String {
  let out = StringBuilder()
  for direction_report in report.reports {
    out.write_string(
      direction_name(direction_report.direction) +
      ": " +
      status_name(direction_report.status) +
      "\n",
    )
    if direction_report.changes.is_empty() {
      out.write_string("  no interface changes\n")
    } else {
      for change in direction_report.changes {
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
  }
  out.to_string()
}

///|
pub fn report_json(report : Report) -> String {
  let out = StringBuilder()
  out.write_string("{\"reports\":[")
  for i, direction_report in report.reports {
    if i > 0 {
      out.write_char(',')
    }
    out.write_string("{\"direction\":")
    out.write_string(json_string(direction_name(direction_report.direction)))
    out.write_string(",\"status\":")
    out.write_string(json_string(status_name(direction_report.status)))
    out.write_string(",\"changes\":[")
    for j, change in direction_report.changes {
      if j > 0 {
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
  }
  out.write_string("]}")
  out.to_string()
}
