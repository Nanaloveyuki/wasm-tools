///|
pub fn parse_manifest(text : String) -> Manifest raise ManifestError {
  let root = @json.parse(
    text,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    error =>
      raise ManifestError::ManifestError("invalid JSON: " + error.to_string())
  }
  let object = object_value(root, "manifest")
  check_keys(
    object,
    ["format_version", "root", "files", "consumers"],
    "manifest",
  )
  let format_version = match object.get("format_version") {
    Some(value) => integer_value(value, "manifest.format_version")
    None =>
      raise ManifestError::ManifestError("manifest.format_version is required")
  }
  if format_version != 1 {
    raise ManifestError::ManifestError("manifest.format_version must be 1")
  }
  let root = match object.get("root") {
    None => "."
    Some(Json::String(value)) => value
    Some(_) =>
      raise ManifestError::ManifestError("manifest.root must be a string")
  }
  if root.is_empty() || contains_control(root) {
    raise ManifestError::ManifestError(
      "manifest.root must be nonempty and contain no control characters",
    )
  }
  let file_values = array_field(object, "files", "manifest")
  if file_values.is_empty() {
    raise ManifestError::ManifestError("manifest.files must not be empty")
  }
  if file_values.length() > 256 {
    raise ManifestError::ManifestError(
      "manifest.files must contain at most 256 entries",
    )
  }
  let files : Array[FileSpec] = []
  for index, value in file_values {
    files.push(parse_file(value, "manifest.files[" + index.to_string() + "]"))
  }
  validate_file_paths(files)
  validate_file_sources(files)

  let consumers = match object.get("consumers") {
    None => []
    Some(value) => {
      let values = array_value(value, "manifest.consumers")
      if values.length() > 16 {
        raise ManifestError::ManifestError(
          "manifest.consumers must contain at most 16 entries",
        )
      }
      let parsed : Array[Consumer] = []
      for index, item in values {
        parsed.push(
          parse_consumer(
            item,
            "manifest.consumers[" + index.to_string() + "]",
            files,
          ),
        )
      }
      validate_consumer_names(parsed)
      parsed
    }
  }
  { format_version, root, files, consumers, }
}

///|
fn parse_file(value : Json, path : String) -> FileSpec raise ManifestError {
  let object = object_value(value, path)
  check_keys(object, ["path", "kind", "encoding", "source"], path)
  let file_path = nonempty_string_field(object, "path", path)
  validate_relative_path(file_path, path + ".path")
  let kind = match object.get("kind") {
    None => FileKind::Asset
    Some(Json::String("asset")) => FileKind::Asset
    Some(Json::String("wasm")) => FileKind::Wasm
    Some(_) =>
      raise ManifestError::ManifestError(path + ".kind must be asset or wasm")
  }
  let encoding = match object.get("encoding") {
    None => Encoding::Identity
    Some(Json::String("identity")) => Encoding::Identity
    Some(Json::String("gzip")) => Encoding::Gzip
    Some(Json::String("br")) => Encoding::Brotli
    Some(_) =>
      raise ManifestError::ManifestError(
        path + ".encoding must be identity, gzip, or br",
      )
  }
  let source = match object.get("source") {
    None => None
    Some(Json::String(value)) => Some(value)
    Some(_) =>
      raise ManifestError::ManifestError(path + ".source must be a string")
  }
  if kind == FileKind::Wasm && encoding != Encoding::Identity {
    raise ManifestError::ManifestError(
      path + ".kind wasm requires identity encoding",
    )
  }
  match (encoding, source) {
    (Encoding::Identity, None) => ()
    (Encoding::Identity, Some(_)) =>
      raise ManifestError::ManifestError(
        path + ".source is only valid for gzip or br files",
      )
    (_, None) =>
      raise ManifestError::ManifestError(
        path + ".source is required for gzip or br files",
      )
    (_, Some(source_path)) => {
      if source_path.is_empty() {
        raise ManifestError::ManifestError(path + ".source must not be empty")
      }
      validate_relative_path(source_path, path + ".source")
    }
  }
  { path: file_path, kind, encoding, source, }
}

///|
fn parse_consumer(
  value : Json,
  path : String,
  files : Array[FileSpec],
) -> Consumer raise ManifestError {
  let object = object_value(value, path)
  check_keys(
    object,
    ["name", "entry", "requires", "export", "args", "expected", "timeout_ms"],
    path,
  )
  let name = nonempty_string_field(object, "name", path)
  validate_consumer_name(name, path + ".name")
  let entry = nonempty_string_field(object, "entry", path)
  validate_relative_path(entry, path + ".entry")
  if !entry.has_suffix(".mjs") {
    raise ManifestError::ManifestError(path + ".entry must end in .mjs")
  }
  let entry_file = find_file(files, entry)
  match entry_file {
    None =>
      raise ManifestError::ManifestError(
        path + ".entry must reference a declared file",
      )
    Some(file) if file.encoding != Encoding::Identity =>
      raise ManifestError::ManifestError(
        path + ".entry must reference an identity file",
      )
    Some(_) => ()
  }
  let requires = match object.get("requires") {
    None => []
    Some(value) => {
      let values = array_value(value, path + ".requires")
      let paths : Array[String] = []
      for index, item in values {
        match item {
          Json::String(required) => {
            validate_relative_path(
              required,
              path + ".requires[" + index.to_string() + "]",
            )
            if !contains_file(files, required) {
              raise ManifestError::ManifestError(
                path + ".requires references an undeclared file: " + required,
              )
            }
            if paths.contains(required) {
              raise ManifestError::ManifestError(
                path + ".requires contains duplicate file: " + required,
              )
            }
            paths.push(required)
          }
          _ =>
            raise ManifestError::ManifestError(
              path + ".requires[" + index.to_string() + "] must be a string",
            )
        }
      }
      paths
    }
  }
  let export_name = nonempty_string_field(object, "export", path)
  let args = match object.get("args") {
    None => []
    Some(value) => array_value(value, path + ".args")
  }
  let expected = match object.get("expected") {
    Some(value) => value
    None => raise ManifestError::ManifestError(path + ".expected is required")
  }
  let timeout_ms = match object.get("timeout_ms") {
    None => 5000
    Some(value) => integer_value(value, path + ".timeout_ms")
  }
  if timeout_ms < 100 || timeout_ms > 60000 {
    raise ManifestError::ManifestError(
      path + ".timeout_ms must be between 100 and 60000",
    )
  }
  { name, entry, requires, export_name, args, expected, timeout_ms, }
}

///|
fn validate_file_paths(files : Array[FileSpec]) -> Unit raise ManifestError {
  for index, file in files {
    let normalized = file.path.to_lower()
    for earlier in 0..<index {
      let prior = files[earlier].path.to_lower()
      if normalized == prior {
        raise ManifestError::ManifestError(
          "manifest.files contains duplicate path ignoring case: " + file.path,
        )
      }
      if normalized.has_prefix(prior + "/") ||
        prior.has_prefix(normalized + "/") {
        raise ManifestError::ManifestError(
          "manifest.files has a file-directory prefix conflict: " + file.path,
        )
      }
    }
  }
}

///|
fn validate_file_sources(files : Array[FileSpec]) -> Unit raise ManifestError {
  for file in files {
    match file.source {
      None => ()
      Some(source_path) => {
        let source = find_file(files, source_path)
        match source {
          None =>
            raise ManifestError::ManifestError(
              "manifest.files source is undeclared: " + source_path,
            )
          Some(source_file) if source_file.encoding != Encoding::Identity =>
            raise ManifestError::ManifestError(
              "manifest.files source must use identity encoding: " + source_path,
            )
          Some(_) => ()
        }
      }
    }
  }
}

///|
fn validate_consumer_names(
  consumers : Array[Consumer],
) -> Unit raise ManifestError {
  for index, consumer in consumers {
    for earlier in 0..<index {
      if consumer.name.to_lower() == consumers[earlier].name.to_lower() {
        raise ManifestError::ManifestError(
          "manifest.consumers contains duplicate name: " + consumer.name,
        )
      }
    }
  }
}

///|
fn validate_consumer_name(
  name : String,
  path : String,
) -> Unit raise ManifestError {
  for char in name {
    if !is_ascii_letter(char) &&
      !is_ascii_digit(char) &&
      char != '_' &&
      char != '-' {
      raise ManifestError::ManifestError(
        path + " may contain only ASCII letters, digits, _ and -",
      )
    }
  }
}

///|
fn validate_relative_path(
  path : String,
  label : String,
) -> Unit raise ManifestError {
  if path.is_empty() || path.has_prefix("/") || path.contains("\\") {
    raise ManifestError::ManifestError(
      label + " must be a portable relative path using / separators",
    )
  }
  for char in path {
    if char.to_int() < 32 ||
      char.to_int() == 127 ||
      contains_char("<>:\"|?*", char) {
      raise ManifestError::ManifestError(
        label + " contains a character not allowed in portable paths",
      )
    }
  }
  for segment in path.split("/") {
    if segment.is_empty() || segment == "." || segment == ".." {
      raise ManifestError::ManifestError(
        label + " must not contain empty, . or .. path segments",
      )
    }
    if segment.has_suffix(".") || segment.has_suffix(" ") {
      raise ManifestError::ManifestError(
        label + " segments must not end in a dot or space",
      )
    }
    let parts = segment.split(".").to_array()
    let stem = parts[0].to_owned().to_upper()
    if is_windows_device_name(stem) {
      raise ManifestError::ManifestError(
        label + " contains a reserved Windows device name",
      )
    }
  }
}

///|
fn is_windows_device_name(stem : String) -> Bool {
  if ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"].contains(stem) {
    return true
  }
  windows_numbered_device(stem, "COM") || windows_numbered_device(stem, "LPT")
}

///|
fn windows_numbered_device(name : String, prefix : String) -> Bool {
  if !name.has_prefix(prefix) {
    return false
  }
  let suffix = name.get_view(start=prefix.length()).unwrap_or("").to_owned()
  if suffix.length() != 1 {
    return false
  }
  let digit = suffix[0]
  (digit >= '1' && digit <= '9') ||
  digit == '¹' ||
  digit == '²' ||
  digit == '³'
}

///|
fn contains_control(value : String) -> Bool {
  for char in value {
    if char.to_int() < 32 || char.to_int() == 127 {
      return true
    }
  }
  false
}

///|
fn contains_char(values : String, target : Char) -> Bool {
  for value in values {
    if value == target {
      return true
    }
  }
  false
}

///|
fn is_ascii_letter(char : Char) -> Bool {
  (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z')
}

///|
fn is_ascii_digit(char : Char) -> Bool {
  char >= '0' && char <= '9'
}

///|
fn find_file(files : Array[FileSpec], path : String) -> FileSpec? {
  for file in files {
    if file.path == path {
      return Some(file)
    }
  }
  None
}

///|
fn contains_file(files : Array[FileSpec], path : String) -> Bool {
  find_file(files, path) is Some(_)
}

///|
fn object_value(
  value : Json,
  path : String,
) -> Map[String, Json] raise ManifestError {
  match value {
    Json::Object(object) => object
    _ => raise ManifestError::ManifestError(path + " must be an object")
  }
}

///|
fn check_keys(
  object : Map[String, Json],
  allowed : Array[String],
  path : String,
) -> Unit raise ManifestError {
  for key in object.keys() {
    if !allowed.contains(key) {
      raise ManifestError::ManifestError(path + " has unknown key: " + key)
    }
  }
}

///|
fn nonempty_string_field(
  object : Map[String, Json],
  key : String,
  path : String,
) -> String raise ManifestError {
  match object.get(key) {
    Some(Json::String(value)) if !value.is_empty() => value
    Some(Json::String(_)) =>
      raise ManifestError::ManifestError(
        path + "." + key + " must not be empty",
      )
    _ =>
      raise ManifestError::ManifestError(path + "." + key + " must be a string")
  }
}

///|
fn array_value(value : Json, path : String) -> Array[Json] raise ManifestError {
  match value {
    Json::Array(values) => values
    _ => raise ManifestError::ManifestError(path + " must be an array")
  }
}

///|
fn array_field(
  object : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise ManifestError {
  match object.get(key) {
    Some(value) => array_value(value, path + "." + key)
    None =>
      raise ManifestError::ManifestError(path + "." + key + " is required")
  }
}

///|
fn integer_value(value : Json, path : String) -> Int32 raise ManifestError {
  match value {
    Json::Number(_) =>
      match @json_number.nonnegative_int32(value) {
        Some(integer) => integer
        None =>
          raise ManifestError::ManifestError(
            path + " must be a nonnegative integer",
          )
      }
    _ => raise ManifestError::ManifestError(path + " must be an integer")
  }
}
