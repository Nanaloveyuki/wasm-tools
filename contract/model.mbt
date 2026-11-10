///|
pub(all) enum Direction {
  Provided
  Required
  Both
} derive(Eq)

///|
pub extend Direction with Eq::{equal, not_equal}

///|
pub(all) enum Status {
  Compatible
  Unknown
  Breaking
} derive(Eq)

///|
pub extend Status with Eq::{equal, not_equal}

///|
pub(all) enum ExternalKind {
  Function
  Table
  Memory
  Global
  Tag
} derive(Eq)

///|
pub extend ExternalKind with Eq::{equal, not_equal}

///|
pub(all) struct Limits {
  minimum : Int64
  maximum : Int64?
} derive(Eq)

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub(all) enum ExternalType {
  Function(Array[String], Array[String])
  Table(String, Limits, Bool)
  Memory(Limits, Bool, Bool, Int32)
  Global(String, Bool)
  Tag(Array[String])
  Unsupported(String)
} derive(Eq)

///|
pub extend ExternalType with Eq::{equal, not_equal}

///|
pub(all) struct Entry {
  import_module : String?
  name : String
  kind : ExternalKind
  type_ : ExternalType
} derive(Eq)

///|
pub extend Entry with Eq::{equal, not_equal}

///|
pub(all) struct Snapshot {
  format_version : Int32
  imports : Array[Entry]
  exports : Array[Entry]
  diagnostics : Array[String]
} derive(Eq)

///|
pub extend Snapshot with Eq::{equal, not_equal}

///|
pub(all) struct Change {
  key : String
  status : Status
  detail : String
} derive(Eq)

///|
pub extend Change with Eq::{equal, not_equal}

///|
pub(all) struct DirectionReport {
  direction : Direction
  status : Status
  changes : Array[Change]
} derive(Eq)

///|
pub extend DirectionReport with Eq::{equal, not_equal}

///|
pub(all) struct Report {
  reports : Array[DirectionReport]
} derive(Eq)

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
