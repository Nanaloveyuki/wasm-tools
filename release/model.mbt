///|
#derive(Eq)
pub(all) struct ImportName {
  import_module : String
  name : String
}

///|
pub extend ImportName with Eq::{equal, not_equal}

///|
pub(all) struct SectionMetric {
  name : String
  bytes : Int32
}

///|
pub(all) struct Facts {
  bytes : Int32
  sha256 : String
  sections : Array[SectionMetric]
  imports : Array[ImportName]
  custom_sections : Array[String]
}

///|
pub(all) struct Rules {
  max_bytes : Int32?
  max_growth_bytes : Int32?
  max_growth_percent : Int32?
  section_budgets : Map[String, Int32]
  allowed_imports : Array[ImportName]?
  required_custom_sections : Array[String]
  forbidden_custom_sections : Array[String]
}

///|
pub(all) struct Processing {
  strip_custom_sections : Array[String]
  optimize : String?
}

///|
pub(all) struct AbiCheck {
  baseline : String
}

///|
pub(all) struct Artifact {
  id : String
  input : String
  baseline : String?
  rules : Rules
  process : Processing
  abi : AbiCheck?
}

///|
pub(all) struct Config {
  format_version : Int32
  artifacts : Array[Artifact]
}

///|
pub(all) struct Finding {
  rule : String
  message : String
  actual : Json
  limit : Json
}

///|
pub(all) suberror ConfigError {
  Invalid(String)
}

///|
pub fn ConfigError::message(self : ConfigError) -> String {
  match self {
    Invalid(message) => message
  }
}
