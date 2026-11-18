///|
#derive(Eq)
pub enum Encoding {
  Identity
  Gzip
  Brotli
}

///|
pub extend Encoding with Eq::{equal, not_equal}

///|
#derive(Eq)
pub enum FileKind {
  Asset
  Wasm
}

///|
pub extend FileKind with Eq::{equal, not_equal}

///|
pub(all) struct FileSpec {
  path : String
  kind : FileKind
  encoding : Encoding
  source : String?
}

///|
pub(all) struct Consumer {
  name : String
  entry : String
  requires : Array[String]
  export_name : String
  args : Array[@json.Json]
  expected : @json.Json
  timeout_ms : Int32
}

///|
pub(all) struct Manifest {
  format_version : Int32
  root : String
  files : Array[FileSpec]
  consumers : Array[Consumer]
}

///|
pub(all) struct FileObservation {
  path : String
  bytes : Int32?
  sha256 : String?
  error : String?
}

///|
pub(all) struct Finding {
  code : String
  path : String
  related_path : String?
  message : String
}

///|
pub suberror ManifestError {
  ManifestError(String)
}

///|
pub fn ManifestError::message(self : ManifestError) -> String {
  match self {
    ManifestError(message) => message
  }
}
