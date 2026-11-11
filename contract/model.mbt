///|
#derive(Eq)
pub(all) enum Direction {
  Provided
  Required
  Both
}

///|
pub extend Direction with Eq::{equal, not_equal}

///|
#derive(Eq)
pub(all) enum Status {
  Compatible
  Unknown
  Breaking
}

///|
pub extend Status with Eq::{equal, not_equal}

///|
#derive(Eq)
pub(all) enum ExternalKind {
  Function
  Table
  Memory
  Global
  Tag
}

///|
pub extend ExternalKind with Eq::{equal, not_equal}

///|
#derive(Eq)
pub(all) struct Limits {
  minimum : Int64
  maximum : Int64?
}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
#derive(Eq)
pub(all) enum ExternalType {
  Function(Array[String], Array[String])
  Table(String, Limits, Bool)
  Memory(Limits, Bool, Bool, Int32)
  Global(String, Bool)
  Tag(Array[String])
  Unsupported(String)
}

///|
pub extend ExternalType with Eq::{equal, not_equal}

///|
#derive(Eq)
pub(all) struct Entry {
  import_module : String?
  name : String
  kind : ExternalKind
  type_ : ExternalType
}

///|
pub extend Entry with Eq::{equal, not_equal}

///|
#derive(Eq)
pub(all) struct Snapshot {
  format_version : Int32
  imports : Array[Entry]
  exports : Array[Entry]
  diagnostics : Array[String]
}

///|
pub extend Snapshot with Eq::{equal, not_equal}

///|
#derive(Eq)
pub(all) struct Change {
  key : String
  status : Status
  detail : String
}

///|
pub extend Change with Eq::{equal, not_equal}

///|
#derive(Eq)
pub(all) struct DirectionReport {
  direction : Direction
  status : Status
  changes : Array[Change]
}

///|
pub extend DirectionReport with Eq::{equal, not_equal}

///|
#derive(Eq)
pub(all) struct Report {
  reports : Array[DirectionReport]
}

///|
pub extend Report with Eq::{equal, not_equal}

///|
pub(all) suberror SnapshotError {
  Invalid(String)
}

///|
pub fn SnapshotError::message(self : SnapshotError) -> String {
  match self {
    Invalid(message) => message
  }
}
