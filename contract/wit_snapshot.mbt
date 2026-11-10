///|
pub fn wit_snapshot_json(snapshot : WitSnapshot) -> String {
  let out = StringBuilder()
  out.write_string("{\"format_version\":")
  out.write_string(snapshot.format_version.to_string())
  out.write_string(",\"namespace\":")
  out.write_string(json_string(snapshot.namespace_name))
  out.write_string(",\"package\":")
  out.write_string(json_string(snapshot.package_name))
  out.write_string(",\"package_version\":")
  match snapshot.package_version {
    Some(version) => out.write_string(json_string(version))
    None => out.write_string("null")
  }
  out.write_string(",\"world\":")
  out.write_string(json_string(snapshot.world))
  out.write_string(",\"imports\":[")
  write_wit_entries(out, snapshot.imports)
  out.write_string("],\"exports\":[")
  write_wit_entries(out, snapshot.exports)
  out.write_string("]}")
  out.to_string()
}

///|
pub fn parse_wit_snapshot(text : String) -> WitSnapshot raise SnapshotError {
  let json = @json.parse(text, reject_duplicate_keys=true) catch {
    e => raise SnapshotError::Invalid("invalid JSON: " + e.to_string())
  }
  guard json
    is {
      "format_version": Number(version, ..),
      "namespace": String(namespace_name),
      "package": String(package_name),
      "package_version": package_version_json,
      "world": String(world),
      "imports": Array(imports),
      "exports": Array(exports),
      ..
    } else {
    raise SnapshotError::Invalid(
      "WIT snapshot must contain format_version, package identity, world, imports, and exports",
    )
  }
  if version != WIT_SNAPSHOT_FORMAT_VERSION.to_double() {
    raise SnapshotError::Invalid(
      "unsupported WIT snapshot format version: " + version.to_string(),
    )
  }
  let package_version = match package_version_json {
    Null => None
    String(value) => Some(value)
    _ =>
      raise SnapshotError::Invalid("package_version must be a string or null")
  }
  let parsed_imports = parse_wit_entries(imports)
  let parsed_exports = parse_wit_entries(exports)
  {
    format_version: WIT_SNAPSHOT_FORMAT_VERSION,
    namespace_name,
    package_name,
    package_version,
    world,
    imports: sorted_wit_entries(parsed_imports),
    exports: sorted_wit_entries(parsed_exports),
  }
}

///|
fn write_wit_entries(out : StringBuilder, entries : Array[WitEntry]) -> Unit {
  let sorted = sorted_wit_entries(entries)
  for i, entry in sorted {
    if i > 0 {
      out.write_char(',')
    }
    out.write_string("{\"name\":")
    out.write_string(json_string(entry.name))
    out.write_string(",\"kind\":")
    out.write_string(json_string(entry.kind))
    out.write_string(",\"signature\":")
    out.write_string(json_string(entry.signature))
    out.write_char('}')
  }
}

///|
fn parse_wit_entries(
  items : Array[Json],
) -> Array[WitEntry] raise SnapshotError {
  let entries : Array[WitEntry] = []
  for item in items {
    guard item
      is {
        "name": String(name),
        "kind": String(kind),
        "signature": String(signature),
        ..
      } else {
      raise SnapshotError::Invalid("WIT snapshot entry has invalid fields")
    }
    entries.push({ name, kind, signature, })
  }
  entries
}

///|
fn sorted_wit_entries(entries : Array[WitEntry]) -> Array[WitEntry] {
  let sorted = entries.copy()
  sorted.sort_by(fn(left, right) {
    let name_order = left.name.lexical_compare(right.name)
    if name_order != 0 {
      name_order
    } else {
      let kind_order = left.kind.lexical_compare(right.kind)
      if kind_order != 0 {
        kind_order
      } else {
        left.signature.lexical_compare(right.signature)
      }
    }
  })
  sorted
}
