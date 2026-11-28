///|
pub fn portable_path_error(path : String) -> String? {
  if path.is_empty() || path.has_prefix("/") || path.contains("\\") {
    return Some("must be a portable relative path using / separators")
  }
  for char in path {
    if char.to_int() < 32 ||
      char.to_int() == 127 ||
      char is ('<' | '>' | ':' | '"' | '|' | '?' | '*') {
      return Some("contains a character not allowed in portable paths")
    }
  }
  for segment in path.split("/") {
    if segment.is_empty() || segment == "." || segment == ".." {
      return Some("must not contain empty, . or .. path segments")
    }
    if segment.has_suffix(".") || segment.has_suffix(" ") {
      return Some("segments must not end in a dot or space")
    }
    let stem = segment.split(".").next().unwrap_or("").to_owned().to_upper()
    if is_windows_device_name(stem) {
      return Some("contains a reserved Windows device name")
    }
  }
  None
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
  guard name.has_prefix(prefix) && name.length() == prefix.length() + 1 else {
    return false
  }
  let digit = name[prefix.length()]
  (digit >= '1' && digit <= '9') || digit is ('¹' | '²' | '³')
}
