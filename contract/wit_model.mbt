///|
pub const WIT_SNAPSHOT_FORMAT_VERSION : Int32 = 1

///|
pub(all) struct WitEntry {
  name : String
  kind : String
  signature : String
} derive(Eq)

///|
pub extend WitEntry with Eq::{equal, not_equal}

///|
pub(all) struct WitSnapshot {
  format_version : Int32
  namespace_name : String
  package_name : String
  package_version : String?
  world : String
  imports : Array[WitEntry]
  exports : Array[WitEntry]
} derive(Eq)

///|
pub extend WitSnapshot with Eq::{equal, not_equal}

///|
pub fn WitSnapshot::new(
  namespace_name : String,
  package_name : String,
  package_version : String?,
  world : String,
  imports : Array[WitEntry],
  exports : Array[WitEntry],
) -> WitSnapshot {
  {
    format_version: WIT_SNAPSHOT_FORMAT_VERSION,
    namespace_name,
    package_name,
    package_version,
    world,
    imports: sorted_wit_entries(imports),
    exports: sorted_wit_entries(exports),
  }
}

///|
pub(all) struct WitReport {
  namespace_name : String
  package_name : String
  baseline_version : String?
  candidate_version : String?
  world : String
  status : Status
  changes : Array[Change]
} derive(Eq)

///|
pub extend WitReport with Eq::{equal, not_equal}
