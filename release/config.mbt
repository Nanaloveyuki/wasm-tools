///|
pub fn parse_config(text : String) -> Config raise ConfigError {
  let root = @json.parse(
    text,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    error => raise ConfigError::Invalid("invalid JSON: " + error.to_string())
  }
  let root = object_value(root, "config")
  check_keys(root, ["format_version", "artifacts"], "config")
  let format_version = integer_field(root, "format_version", "config")
  if format_version != 1 {
    raise ConfigError::Invalid("format_version must be 1")
  }
  let items = array_field(root, "artifacts", "config")
  if items.is_empty() {
    raise ConfigError::Invalid("artifacts must not be empty")
  }
  let artifacts : Array[Artifact] = []
  let ids : Array[String] = []
  for index, item in items {
    let path = "artifacts[" + index.to_string() + "]"
    let artifact = parse_artifact(item, path)
    let normalized_id = artifact.id.to_lower()
    if contains_string(ids, normalized_id) {
      raise ConfigError::Invalid("duplicate artifact id: " + artifact.id)
    }
    ids.push(normalized_id)
    artifacts.push(artifact)
  }
  { format_version, artifacts, }
}

///|
fn parse_artifact(value : Json, path : String) -> Artifact raise ConfigError {
  let object = object_value(value, path)
  check_keys(
    object,
    ["id", "input", "baseline", "rules", "process", "abi"],
    path,
  )
  let id = string_field(object, "id", path)
  validate_artifact_id(id)
  let input = nonempty_string_field(object, "input", path)
  let baseline = optional_nonempty_string_field(object, "baseline", path)
  let rules = match object.get("rules") {
    Some(value) => parse_rules(value, path + ".rules")
    None => raise ConfigError::Invalid(path + ".rules is required")
  }
  let process = match object.get("process") {
    Some(value) => parse_processing(value, path + ".process")
    None => { strip_custom_sections: [], optimize: None, }
  }
  let abi = match object.get("abi") {
    Some(Json::Null) | None => None
    Some(value) => Some(parse_abi(value, path + ".abi"))
  }
  validate_rule_conflicts(rules, process, path)
  { id, input, baseline, rules, process, abi, }
}

///|
fn parse_rules(value : Json, path : String) -> Rules raise ConfigError {
  let object = object_value(value, path)
  check_keys(
    object,
    [
      "max_bytes", "max_growth_bytes", "max_growth_percent", "section_budgets", "allowed_imports",
      "required_custom_sections", "forbidden_custom_sections",
    ],
    path,
  )
  let max_bytes = optional_nonnegative_integer(object, "max_bytes", path)
  let max_growth_bytes = optional_nonnegative_integer(
    object, "max_growth_bytes", path,
  )
  let max_growth_percent = optional_nonnegative_integer(
    object, "max_growth_percent", path,
  )
  let section_budgets = parse_section_budgets(object, path)
  let allowed_imports = parse_allowed_imports(object, path)
  let required_custom_sections = optional_string_array(
    object, "required_custom_sections", path,
  )
  let forbidden_custom_sections = optional_string_array(
    object, "forbidden_custom_sections", path,
  )
  reject_duplicates(
    required_custom_sections,
    path + ".required_custom_sections",
  )
  reject_duplicates(
    forbidden_custom_sections,
    path + ".forbidden_custom_sections",
  )
  {
    max_bytes,
    max_growth_bytes,
    max_growth_percent,
    section_budgets,
    allowed_imports,
    required_custom_sections,
    forbidden_custom_sections,
  }
}

///|
fn parse_processing(
  value : Json,
  path : String,
) -> Processing raise ConfigError {
  let object = object_value(value, path)
  check_keys(object, ["strip_custom_sections", "optimize"], path)
  let strip_custom_sections = optional_string_array(
    object, "strip_custom_sections", path,
  )
  reject_duplicates(strip_custom_sections, path + ".strip_custom_sections")
  let optimize = optional_nonempty_string_field(object, "optimize", path)
  match optimize {
    Some(level) =>
      if !contains_string(["-O1", "-O2", "-O3", "-O4", "-Os", "-Oz"], level) {
        raise ConfigError::Invalid(
          path + ".optimize must be one of -O1, -O2, -O3, -O4, -Os, or -Oz",
        )
      }
    None => ()
  }
  { strip_custom_sections, optimize, }
}

///|
fn parse_abi(value : Json, path : String) -> AbiCheck raise ConfigError {
  let object = object_value(value, path)
  check_keys(object, ["baseline"], path)
  let baseline = nonempty_string_field(object, "baseline", path)
  { baseline, }
}

///|
fn parse_section_budgets(
  object : Map[String, Json],
  path : String,
) -> Map[String, Int32] raise ConfigError {
  let budgets : Map[String, Int32] = Map([])
  match object.get("section_budgets") {
    None => budgets
    Some(Json::Object(values)) => {
      for name, value in values {
        if !valid_section_label(name) {
          raise ConfigError::Invalid(
            path + ".section_budgets has an unsupported section label: " + name,
          )
        }
        let bytes = integer_value(value, path + ".section_budgets." + name)
        if bytes < 0 {
          raise ConfigError::Invalid(
            path + ".section_budgets." + name + " must not be negative",
          )
        }
        budgets.set(name, bytes)
      }
      budgets
    }
    Some(_) =>
      raise ConfigError::Invalid(path + ".section_budgets must be an object")
  }
}

///|
fn parse_allowed_imports(
  object : Map[String, Json],
  path : String,
) -> Array[ImportName]? raise ConfigError {
  match object.get("allowed_imports") {
    None | Some(Json::Null) => None
    Some(Json::Array(values)) => {
      let imports : Array[ImportName] = []
      for index, value in values {
        let item_path = path + ".allowed_imports[" + index.to_string() + "]"
        let item = object_value(value, item_path)
        check_keys(item, ["module", "name"], item_path)
        let import_module = string_field(item, "module", item_path)
        let name = string_field(item, "name", item_path)
        let allowed_import = { import_module, name, }
        if imports.contains(allowed_import) {
          raise ConfigError::Invalid(
            item_path + " duplicates an allowed import",
          )
        }
        imports.push(allowed_import)
      }
      Some(imports)
    }
    Some(_) =>
      raise ConfigError::Invalid(path + ".allowed_imports must be an array")
  }
}

///|
fn validate_rule_conflicts(
  rules : Rules,
  process : Processing,
  path : String,
) -> Unit raise ConfigError {
  for name in rules.required_custom_sections {
    if contains_string(rules.forbidden_custom_sections, name) {
      raise ConfigError::Invalid(
        path + ".rules both requires and forbids custom section " + name,
      )
    }
    if contains_string(process.strip_custom_sections, name) {
      raise ConfigError::Invalid(
        path + ".process strips required custom section " + name,
      )
    }
  }
}

///|
fn validate_artifact_id(id : String) -> Unit raise ConfigError {
  if id.is_empty() {
    raise ConfigError::Invalid("artifact id must not be empty")
  }
  for char in id {
    if !is_ascii_letter(char) &&
      !is_ascii_digit(char) &&
      char != '_' &&
      char != '-' {
      raise ConfigError::Invalid(
        "artifact id may contain only ASCII letters, digits, _ and -: " + id,
      )
    }
  }
  let upper = id.to_upper()
  if contains_string(["CON", "PRN", "AUX", "NUL"], upper) ||
    windows_numbered_device(upper, "COM") ||
    windows_numbered_device(upper, "LPT") {
    raise ConfigError::Invalid(
      "artifact id is a reserved Windows device name: " + id,
    )
  }
}

///|
fn windows_numbered_device(id : String, prefix : String) -> Bool {
  if !id.has_prefix(prefix) {
    return false
  }
  let suffix = id.get_view(start=prefix.length()).unwrap_or("").to_owned()
  if suffix.length() != 1 {
    return false
  }
  let digit = suffix[0]
  digit >= '1' && digit <= '9'
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
fn valid_section_label(name : String) -> Bool {
  if contains_string(
      [
        "type", "import", "function", "table", "memory", "global", "export", "start",
        "element", "code", "data", "data-count", "tag",
      ],
      name,
    ) {
    return true
  }
  name.has_prefix("custom:")
}

///|
fn object_value(
  value : Json,
  path : String,
) -> Map[String, Json] raise ConfigError {
  match value {
    Json::Object(object) => object
    _ => raise ConfigError::Invalid(path + " must be an object")
  }
}

///|
fn check_keys(
  object : Map[String, Json],
  allowed : Array[String],
  path : String,
) -> Unit raise ConfigError {
  for key in object.keys() {
    if !contains_string(allowed, key) {
      raise ConfigError::Invalid(path + " has unknown key: " + key)
    }
  }
}

///|
fn string_field(
  object : Map[String, Json],
  key : String,
  path : String,
) -> String raise ConfigError {
  match object.get(key) {
    Some(Json::String(value)) => value
    _ => raise ConfigError::Invalid(path + "." + key + " must be a string")
  }
}

///|
fn nonempty_string_field(
  object : Map[String, Json],
  key : String,
  path : String,
) -> String raise ConfigError {
  let value = string_field(object, key, path)
  if value.is_empty() {
    raise ConfigError::Invalid(path + "." + key + " must not be empty")
  }
  value
}

///|
fn optional_string_field(
  object : Map[String, Json],
  key : String,
  path : String,
) -> String? raise ConfigError {
  match object.get(key) {
    None | Some(Json::Null) => None
    Some(Json::String(value)) => Some(value)
    Some(_) =>
      raise ConfigError::Invalid(path + "." + key + " must be a string or null")
  }
}

///|
fn optional_nonempty_string_field(
  object : Map[String, Json],
  key : String,
  path : String,
) -> String? raise ConfigError {
  match optional_string_field(object, key, path) {
    Some(value) => {
      if value.is_empty() {
        raise ConfigError::Invalid(path + "." + key + " must not be empty")
      }
      Some(value)
    }
    None => None
  }
}

///|
fn array_field(
  object : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise ConfigError {
  match object.get(key) {
    Some(Json::Array(values)) => values
    _ => raise ConfigError::Invalid(path + "." + key + " must be an array")
  }
}

///|
fn optional_string_array(
  object : Map[String, Json],
  key : String,
  path : String,
) -> Array[String] raise ConfigError {
  match object.get(key) {
    None => []
    Some(Json::Array(values)) => {
      let strings : Array[String] = []
      for index, value in values {
        match value {
          Json::String(text) => strings.push(text)
          _ =>
            raise ConfigError::Invalid(
              path + "." + key + "[" + index.to_string() + "] must be a string",
            )
        }
      }
      strings
    }
    Some(_) =>
      raise ConfigError::Invalid(path + "." + key + " must be an array")
  }
}

///|
fn optional_nonnegative_integer(
  object : Map[String, Json],
  key : String,
  path : String,
) -> Int32? raise ConfigError {
  match object.get(key) {
    None | Some(Json::Null) => None
    Some(value) => {
      let integer = integer_value(value, path + "." + key)
      if integer < 0 {
        raise ConfigError::Invalid(path + "." + key + " must not be negative")
      }
      Some(integer)
    }
  }
}

///|
fn integer_field(
  object : Map[String, Json],
  key : String,
  path : String,
) -> Int32 raise ConfigError {
  match object.get(key) {
    Some(value) => integer_value(value, path + "." + key)
    None => raise ConfigError::Invalid(path + "." + key + " is required")
  }
}

///|
fn integer_value(value : Json, path : String) -> Int32 raise ConfigError {
  match value {
    Json::Number(_) =>
      match @json_number.nonnegative_int32(value) {
        Some(integer) => integer
        None =>
          raise ConfigError::Invalid(
            path + " must be a nonnegative 32-bit integer",
          )
      }
    _ => raise ConfigError::Invalid(path + " must be an integer")
  }
}

///|
fn reject_duplicates(
  values : Array[String],
  path : String,
) -> Unit raise ConfigError {
  for index, value in values {
    for earlier in 0..<index {
      if values[earlier] == value {
        raise ConfigError::Invalid(path + " contains duplicate value: " + value)
      }
    }
  }
}

///|
fn contains_string(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}
