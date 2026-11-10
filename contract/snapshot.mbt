///|
pub const SNAPSHOT_FORMAT_VERSION : Int32 = 1

///|
pub fn Snapshot::new(
  imports : Array[Entry],
  exports : Array[Entry],
) -> Snapshot {
  {
    format_version: SNAPSHOT_FORMAT_VERSION,
    imports: sorted_entries(imports),
    exports: sorted_entries(exports),
    diagnostics: [],
  }
}

///|
pub fn snapshot_json(snapshot : Snapshot) -> String {
  let out = StringBuilder()
  out.write_string("{\"format_version\":")
  out.write_string(snapshot.format_version.to_string())
  out.write_string(",\"imports\":[")
  write_entries(out, snapshot.imports)
  out.write_string("],\"exports\":[")
  write_entries(out, snapshot.exports)
  out.write_string("],\"diagnostics\":[")
  let diagnostics = snapshot.diagnostics.copy()
  diagnostics.sort_by(fn(left, right) {
    if left < right {
      -1
    } else if left > right {
      1
    } else {
      0
    }
  })
  for i, diagnostic in diagnostics {
    if i > 0 {
      out.write_char(',')
    }
    out.write_string(json_string(diagnostic))
  }
  out.write_string("]}")
  out.to_string()
}

///|
pub fn parse_snapshot(text : String) -> Snapshot raise SnapshotError {
  let json = @json.parse(text, reject_duplicate_keys=true) catch {
    e => raise SnapshotError::Invalid("invalid JSON: " + e.to_string())
  }
  guard json
    is {
      "format_version": Number(version, ..),
      "imports": Array(imports),
      "exports": Array(exports),
      "diagnostics": Array(diagnostics),
      ..
    } else {
    raise SnapshotError::Invalid(
      "snapshot must contain format_version, imports, exports, and diagnostics",
    )
  }
  if version != SNAPSHOT_FORMAT_VERSION.to_double() {
    raise SnapshotError::Invalid(
      "unsupported snapshot format version: " + version.to_string(),
    )
  }
  let parsed_imports : Array[Entry] = []
  for item in imports {
    let entry = parse_entry(item)
    if entry.import_module is None {
      raise SnapshotError::Invalid("import entry must have a module name")
    }
    parsed_imports.push(entry)
  }
  let parsed_exports : Array[Entry] = []
  for item in exports {
    let entry = parse_entry(item)
    if entry.import_module is Some(_) {
      raise SnapshotError::Invalid("export entry must not have a module name")
    }
    parsed_exports.push(entry)
  }
  let parsed_diagnostics : Array[String] = []
  for item in diagnostics {
    match item {
      String(value) => parsed_diagnostics.push(value)
      _ => raise SnapshotError::Invalid("snapshot diagnostics must be strings")
    }
  }
  {
    format_version: SNAPSHOT_FORMAT_VERSION,
    imports: sorted_entries(parsed_imports),
    exports: sorted_entries(parsed_exports),
    diagnostics: parsed_diagnostics,
  }
}

///|
fn sorted_entries(entries : Array[Entry]) -> Array[Entry] {
  let sorted = entries.copy()
  sorted.sort_by(fn(left, right) {
    let left_key = entry_key(left)
    let right_key = entry_key(right)
    if left_key < right_key {
      -1
    } else if left_key > right_key {
      1
    } else {
      let left_type = external_type_key(left.type_)
      let right_type = external_type_key(right.type_)
      if left_type < right_type {
        -1
      } else if left_type > right_type {
        1
      } else {
        0
      }
    }
  })
  sorted
}

///|
fn write_entries(out : StringBuilder, entries : Array[Entry]) -> Unit {
  let sorted = sorted_entries(entries)
  for i, entry in sorted {
    if i > 0 {
      out.write_char(',')
    }
    out.write_string("{\"module\":")
    match entry.import_module {
      Some(import_module) => out.write_string(json_string(import_module))
      None => out.write_string("null")
    }
    out.write_string(",\"name\":")
    out.write_string(json_string(entry.name))
    out.write_string(",\"kind\":")
    out.write_string(json_string(kind_name(entry.kind)))
    out.write_string(",\"type\":")
    write_external_type(out, entry.type_)
    out.write_char('}')
  }
}

///|
fn write_external_type(out : StringBuilder, type_ : ExternalType) -> Unit {
  match type_ {
    Function(params, results) => {
      out.write_string("{\"tag\":\"function\",\"params\":")
      write_strings(out, params)
      out.write_string(",\"results\":")
      write_strings(out, results)
      out.write_char('}')
    }
    Table(element, limits, table64) => {
      out.write_string("{\"tag\":\"table\",\"element\":")
      out.write_string(json_string(element))
      write_limits(out, limits)
      out.write_string(",\"table64\":")
      out.write_string(table64.to_string())
      out.write_char('}')
    }
    Memory(limits, memory64, shared, page_size_log2) => {
      out.write_string("{\"tag\":\"memory\"")
      write_limits(out, limits)
      out.write_string(",\"memory64\":")
      out.write_string(memory64.to_string())
      out.write_string(",\"shared\":")
      out.write_string(shared.to_string())
      out.write_string(",\"page_size_log2\":")
      out.write_string(page_size_log2.to_string())
      out.write_char('}')
    }
    Global(value_type, mutable) => {
      out.write_string("{\"tag\":\"global\",\"value_type\":")
      out.write_string(json_string(value_type))
      out.write_string(",\"mutable\":")
      out.write_string(mutable.to_string())
      out.write_char('}')
    }
    Tag(params) => {
      out.write_string("{\"tag\":\"tag\",\"params\":")
      write_strings(out, params)
      out.write_char('}')
    }
    Unsupported(reason) => {
      out.write_string("{\"tag\":\"unsupported\",\"reason\":")
      out.write_string(json_string(reason))
      out.write_char('}')
    }
  }
}

///|
fn write_limits(out : StringBuilder, limits : Limits) -> Unit {
  out.write_string(",\"minimum\":")
  out.write_string(json_string(limits.minimum.to_string()))
  out.write_string(",\"maximum\":")
  match limits.maximum {
    Some(maximum) => out.write_string(json_string(maximum.to_string()))
    None => out.write_string("null")
  }
}

///|
fn write_strings(out : StringBuilder, values : Array[String]) -> Unit {
  out.write_char('[')
  for i, value in values {
    if i > 0 {
      out.write_char(',')
    }
    out.write_string(json_string(value))
  }
  out.write_char(']')
}

///|
fn json_string(value : String) -> String {
  Json::string(value).stringify()
}

///|
fn kind_name(kind : ExternalKind) -> String {
  match kind {
    Function => "function"
    Table => "table"
    Memory => "memory"
    Global => "global"
    Tag => "tag"
  }
}

///|
fn entry_key(entry : Entry) -> String {
  let import_module = match entry.import_module {
    Some(value) => value.length().to_string() + ":" + value
    None => "-:"
  }
  import_module +
  entry.name.length().to_string() +
  ":" +
  entry.name +
  kind_name(entry.kind)
}

///|
fn external_type_key(type_ : ExternalType) -> String {
  let out = StringBuilder()
  write_external_type(out, type_)
  out.to_string()
}

///|
fn parse_entry(json : Json) -> Entry raise SnapshotError {
  guard json
    is {
      "module": module_json,
      "name": String(name),
      "kind": String(kind),
      "type": type_json,
      ..
    } else {
    raise SnapshotError::Invalid("snapshot entry has invalid fields")
  }
  let import_module = match module_json {
    Null => None
    String(value) => Some(value)
    _ => raise SnapshotError::Invalid("entry module must be a string or null")
  }
  let kind = parse_kind(kind)
  let type_ = parse_external_type(type_json)
  if !type_matches_kind(kind, type_) {
    raise SnapshotError::Invalid("entry kind does not match its type tag")
  }
  { import_module, name, kind, type_, }
}

///|
fn parse_kind(text : String) -> ExternalKind raise SnapshotError {
  match text {
    "function" => Function
    "table" => Table
    "memory" => Memory
    "global" => Global
    "tag" => Tag
    _ => raise SnapshotError::Invalid("unknown external kind: " + text)
  }
}

///|
fn type_matches_kind(kind : ExternalKind, type_ : ExternalType) -> Bool {
  match (kind, type_) {
    (Function, Function(_, _))
    | (Table, Table(_, _, _))
    | (Memory, Memory(_, _, _, _))
    | (Global, Global(_, _))
    | (Tag, Tag(_))
    | (_, Unsupported(_)) => true
    _ => false
  }
}

///|
fn parse_external_type(json : Json) -> ExternalType raise SnapshotError {
  guard json is { "tag": String(tag), .. } else {
    raise SnapshotError::Invalid("entry type must have a tag")
  }
  match tag {
    "function" => {
      let params = require_strings(json, "params")
      let results = require_strings(json, "results")
      Function(params, results)
    }
    "table" => {
      let element = require_string(json, "element")
      let limits = parse_limits(json)
      let table64 = require_bool(json, "table64")
      Table(element, limits, table64)
    }
    "memory" => {
      let limits = parse_limits(json)
      let memory64 = require_bool(json, "memory64")
      let shared = require_bool(json, "shared")
      let page_size_log2 = require_int32(json, "page_size_log2")
      Memory(limits, memory64, shared, page_size_log2)
    }
    "global" => {
      let value_type = require_string(json, "value_type")
      let mutable = require_bool(json, "mutable")
      Global(value_type, mutable)
    }
    "tag" => Tag(require_strings(json, "params"))
    "unsupported" => Unsupported(require_string(json, "reason"))
    _ => raise SnapshotError::Invalid("unknown external type tag: " + tag)
  }
}

///|
fn parse_limits(json : Json) -> Limits raise SnapshotError {
  let minimum_text = require_string(json, "minimum")
  let minimum = @str.parse_int64(minimum_text) catch {
    _ => raise SnapshotError::Invalid("invalid minimum limit")
  }
  let maximum = match json {
    { "maximum": Null, .. } => None
    { "maximum": String(value), .. } =>
      Some(
        @str.parse_int64(value) catch {
          _ => raise SnapshotError::Invalid("invalid maximum limit")
        },
      )
    _ => raise SnapshotError::Invalid("maximum limit must be a string or null")
  }
  if minimum < 0 {
    raise SnapshotError::Invalid("minimum limit must not be negative")
  }
  match maximum {
    Some(value) =>
      if value < minimum {
        raise SnapshotError::Invalid(
          "maximum limit must not be less than minimum",
        )
      }
    None => ()
  }
  { minimum, maximum, }
}

///|
fn require_string(json : Json, key : String) -> String raise SnapshotError {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(String(value)) => value
        _ => raise SnapshotError::Invalid("expected string field: " + key)
      }
    _ => raise SnapshotError::Invalid("expected object field: " + key)
  }
}

///|
fn require_bool(json : Json, key : String) -> Bool raise SnapshotError {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(True) => true
        Some(False) => false
        _ => raise SnapshotError::Invalid("expected boolean field: " + key)
      }
    _ => raise SnapshotError::Invalid("expected object field: " + key)
  }
}

///|
fn require_int32(json : Json, key : String) -> Int32 raise SnapshotError {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(Number(value, ..)) => {
          let integer = value.to_int()
          if integer.to_double() != value {
            raise SnapshotError::Invalid("expected integer field: " + key)
          }
          integer
        }
        _ => raise SnapshotError::Invalid("expected integer field: " + key)
      }
    _ => raise SnapshotError::Invalid("expected object field: " + key)
  }
}

///|
fn require_strings(
  json : Json,
  key : String,
) -> Array[String] raise SnapshotError {
  match json {
    Object(object) =>
      match object.get(key) {
        Some(Array(values)) => {
          let strings : Array[String] = []
          for value in values {
            match value {
              String(text) => strings.push(text)
              _ =>
                raise SnapshotError::Invalid(
                  "expected string array field: " + key,
                )
            }
          }
          strings
        }
        _ => raise SnapshotError::Invalid("expected array field: " + key)
      }
    _ => raise SnapshotError::Invalid("expected object field: " + key)
  }
}
