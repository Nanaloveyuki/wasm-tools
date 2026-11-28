///|
const BUNDLE_ARCHIVE_LIMIT : Int32 = 72 * 1024 * 1024

///|
const BUNDLE_ARCHIVE_FILE_LIMIT : Int32 = 64 * 1024 * 1024

///|
async fn bundle_read_npm_archive(
  archive : String,
  node : String,
) -> Map[String, Bytes] raise @cli.CliError {
  let encoded = bundle_read_archive_input(archive)
  let tar = bundle_decode_bytes(encoded, "gzip", BUNDLE_ARCHIVE_LIMIT, node)
  bundle_read_npm_tar(tar)
}

///|
async fn bundle_read_archive_input(
  archive : String,
) -> Bytes raise @cli.CliError {
  let kind = @fs.kind(archive) catch {
    error =>
      raise @cli.CliError::Io(
        "cannot inspect npm archive: " + error.to_string(),
      )
  }
  if kind != Regular {
    raise @cli.CliError::Io("npm archive must be a regular file")
  }
  let input = @fs.open(archive, mode=ReadOnly) catch {
    error =>
      raise @cli.CliError::Io("cannot open npm archive: " + error.to_string())
  }
  defer input.close()
  let size = input.size() catch {
    error =>
      raise @cli.CliError::Io("cannot size npm archive: " + error.to_string())
  }
  if size > BUNDLE_ARCHIVE_LIMIT.to_int64() {
    raise @cli.CliError::Invalid("npm archive exceeds 72 MiB")
  }
  let data = input.read_exactly(size.to_int()) catch {
    error =>
      raise @cli.CliError::Io(
        "cannot read npm archive: " + Error::to_string(error),
      )
  }
  let trailing = input.read() catch {
    error =>
      raise @cli.CliError::Io(
        "cannot finish reading npm archive: " + Error::to_string(error),
      )
  }
  if trailing is Some(_) {
    raise @cli.CliError::Io("npm archive grew while being read")
  }
  data
}

///|
priv struct BundleTarMetadata {
  path : String?
  size : Int32?
}

///|
priv struct BundleTarPath {
  segment : String
  mut explicit : Bool
  directory : Bool
  children : Map[String, BundleTarPath]
}

///|
fn bundle_read_npm_tar(tar : Bytes) -> Map[String, Bytes] raise @cli.CliError {
  let files : Map[String, Bytes] = Map([])
  let paths : Map[String, BundleTarPath] = Map([])
  let path_count = Ref(0)
  let mut root_seen = false
  let mut pending : BundleTarMetadata? = None
  let mut offset = 0
  let mut headers = 0
  let mut file_bytes = 0
  while tar.length() - offset >= 512 {
    let header = tar[offset:offset + 512]
    if bundle_tar_is_zero(header) {
      if pending is Some(_) ||
        tar.length() - offset < 1024 ||
        (tar.length() - offset) % 512 != 0 ||
        !bundle_tar_is_zero(tar[offset:]) {
        raise @cli.CliError::Invalid("invalid npm archive end marker")
      }
      bundle_check_npm_metadata(files)
      return files
    }
    if headers >= 4096 {
      raise @cli.CliError::Invalid(
        "npm archive contains more than 4096 tar headers",
      )
    }
    headers += 1
    let kind = header[156]
    let posix = bundle_check_tar_header(header)
    let stored_size = bundle_tar_octal(header[124:136])
    let is_metadata = kind == b'x' || kind == b'L'
    let size = match pending {
      Some({ size: Some(size), .. }) if !is_metadata => size.to_int64()
      _ => stored_size
    }
    let data_offset = offset + 512
    let padded_size = (size + 511L) / 512L * 512L
    if padded_size > (tar.length() - data_offset).to_int64() {
      raise @cli.CliError::Invalid("truncated npm tar entry")
    }
    let data_end = data_offset + size.to_int()
    let data = tar[data_offset:data_end]
    offset = data_offset + padded_size.to_int()
    if !bundle_tar_is_zero(tar[data_end:offset]) {
      raise @cli.CliError::Invalid("invalid npm tar entry padding")
    }
    if is_metadata {
      if pending is Some(_) || size > 65536L {
        raise @cli.CliError::Invalid(
          "unexpected or oversized npm tar metadata header",
        )
      }
      pending = Some(
        if kind == b'x' {
          bundle_tar_pax(data)
        } else {
          { path: Some(bundle_tar_path_string(data)), size: None, }
        },
      )
      continue
    }
    let directory = kind == b'5'
    if !(directory || kind == b'0' || kind == b'\x00') {
      raise @cli.CliError::Invalid(
        "unsupported npm tar entry type: " + kind.to_int().to_string(),
      )
    }
    if directory && size != 0L {
      raise @cli.CliError::Invalid("npm tar directory has a body")
    }
    let path = match pending {
      Some({ path: Some(path), .. }) => path
      _ => bundle_tar_header_path(header, posix)
    }
    pending = None
    if directory && (path == "package/" || path == "package") {
      if root_seen {
        raise @cli.CliError::Invalid("duplicate npm tar package directory")
      }
      root_seen = true
      continue
    }
    guard path.has_prefix("package/") else {
      raise @cli.CliError::Invalid(
        "npm tar entry must start with package/: " +
        Json::string(path).stringify(),
      )
    }
    let end = if directory && path.has_suffix("/") {
      path.length() - 1
    } else {
      path.length()
    }
    let relative = path[8:end].to_owned()
    bundle_validate_archive_path(relative)
    bundle_index_tar_path(paths, relative, directory, path_count)
    if !directory {
      file_bytes += data.length()
      if file_bytes > BUNDLE_ARCHIVE_FILE_LIMIT {
        raise @cli.CliError::Invalid("npm archive file contents exceed 64 MiB")
      }
      files[relative] = data.to_owned()
    }
  }
  raise @cli.CliError::Invalid("npm tar archive ends before its end marker")
}

///|
fn bundle_check_npm_metadata(
  files : Map[String, Bytes],
) -> Unit raise @cli.CliError {
  guard files.get("package.json") is Some(bytes) else {
    raise @cli.CliError::Invalid("npm archive is missing package/package.json")
  }
  let start = if bytes.length() >= 3 && bytes[:3] == b"\xef\xbb\xbf"[:] {
    3
  } else {
    0
  }
  let text = @utf8.decode(bytes[start:]) catch {
    _ => raise @cli.CliError::Invalid("npm archive package.json is not UTF-8")
  }
  let metadata = @json.parse(text) catch {
    error =>
      raise @cli.CliError::Invalid(
        "invalid npm archive package.json: " + error.to_string(),
      )
  }
  guard metadata is Object(_) else {
    raise @cli.CliError::Invalid(
      "npm archive package.json must be a JSON object",
    )
  }
}

///|
fn bundle_tar_is_zero(bytes : BytesView) -> Bool {
  for byte in bytes {
    if byte != b'\x00' {
      return false
    }
  }
  true
}

///|
fn bundle_check_tar_header(header : BytesView) -> Bool raise @cli.CliError {
  let magic = header[257:265]
  let posix = magic == b"ustar\x0000"[:]
  if !posix && magic != b"ustar  \x00"[:] {
    raise @cli.CliError::Invalid("invalid npm tar header format")
  }
  let mut checksum = 0
  for index, byte in header {
    checksum += (if index >= 148 && index < 156 { b' ' } else { byte }).to_int()
  }
  if checksum.to_int64() != bundle_tar_octal(header[148:156]) {
    raise @cli.CliError::Invalid("invalid npm tar header checksum")
  }
  posix
}

///|
fn bundle_tar_octal(bytes : BytesView) -> Int64 raise @cli.CliError {
  let mut value = 0L
  let mut digits = false
  let mut ended = false
  for byte in bytes {
    if !ended && byte >= b'0' && byte <= b'7' {
      value = value * 8L + (byte.to_int() - b'0'.to_int()).to_int64()
      digits = true
    } else if byte == b' ' || byte == b'\x00' {
      ended = ended || digits || byte == b'\x00'
    } else {
      raise @cli.CliError::Invalid("invalid octal number in npm tar header")
    }
  }
  guard digits else {
    raise @cli.CliError::Invalid("missing octal number in npm tar header")
  }
  value
}

///|
fn bundle_tar_header_path(
  header : BytesView,
  posix : Bool,
) -> String raise @cli.CliError {
  let name = bundle_tar_path_string(header[:100])
  let prefix = if posix { bundle_tar_path_string(header[345:500]) } else { "" }
  if prefix.is_empty() {
    name
  } else {
    prefix + "/" + name
  }
}

///|
fn bundle_tar_path_string(bytes : BytesView) -> String raise @cli.CliError {
  let end = bundle_tar_find(bytes, b'\x00', 0).unwrap_or(bytes.length())
  if !bundle_tar_is_zero(bytes[end:]) {
    raise @cli.CliError::Invalid("invalid npm tar path padding")
  }
  bundle_tar_utf8(bytes[:end])
}

///|
fn bundle_tar_utf8(bytes : BytesView) -> String raise @cli.CliError {
  @utf8.decode(bytes) catch {
    _ => raise @cli.CliError::Invalid("npm tar metadata is not UTF-8")
  }
}

///|
fn bundle_tar_find(bytes : BytesView, key : Byte, from : Int32) -> Int32? {
  for i in from..<bytes.length() {
    if bytes[i] == key {
      return Some(i)
    }
  }
  None
}

///|
fn bundle_tar_pax(data : BytesView) -> BundleTarMetadata raise @cli.CliError {
  let keys : Map[String, Unit] = Map([])
  let mut path = None
  let mut size = None
  let mut pos = 0
  while pos < data.length() {
    guard bundle_tar_find(data, b' ', pos) is Some(space) else {
      raise @cli.CliError::Invalid("missing npm tar PAX record length")
    }
    let length = bundle_tar_decimal(data[pos:space])
    if length > data.length() - pos || length <= space - pos + 3 {
      raise @cli.CliError::Invalid("invalid npm tar PAX record length")
    }
    let end = pos + length
    if data[end - 1] != b'\n' {
      raise @cli.CliError::Invalid("invalid npm tar PAX record terminator")
    }
    let record = data[space + 1:end - 1]
    guard bundle_tar_find(record, b'=', 0) is Some(equals) && equals != 0 else {
      raise @cli.CliError::Invalid("invalid npm tar PAX record field")
    }
    let key = bundle_tar_utf8(record[:equals])
    if keys.contains(key) {
      raise @cli.CliError::Invalid(
        "duplicate npm tar PAX key: " + Json::string(key).stringify(),
      )
    }
    keys[key] = ()
    let value = record[equals + 1:]
    match key {
      "path" => path = Some(bundle_tar_utf8(value))
      "size" => size = Some(bundle_tar_decimal(value))
      "mtime"
      | "atime"
      | "ctime"
      | "uid"
      | "gid"
      | "uname"
      | "gname"
      | "dev"
      | "ino"
      | "nlink"
      | "comment" => ()
      _ =>
        raise @cli.CliError::Invalid(
          "unsupported npm tar PAX key: " + Json::string(key).stringify(),
        )
    }
    pos = end
  }
  { path, size, }
}

///|
fn bundle_tar_decimal(bytes : BytesView) -> Int32 raise @cli.CliError {
  if bytes.is_empty() {
    raise @cli.CliError::Invalid(
      "missing decimal number in npm tar PAX metadata",
    )
  }
  let mut value = 0
  for byte in bytes {
    let digit = byte.to_int() - b'0'.to_int()
    if digit < 0 || digit > 9 || value > (BUNDLE_ARCHIVE_LIMIT - digit) / 10 {
      raise @cli.CliError::Invalid(
        "invalid decimal number in npm tar PAX metadata",
      )
    }
    value = value * 10 + digit
  }
  value
}

///|
fn bundle_index_tar_path(
  paths : Map[String, BundleTarPath],
  path : String,
  directory : Bool,
  path_count : Ref[Int32],
) -> Unit raise @cli.CliError {
  let parts = path.split("/").to_array()
  let mut current = paths
  for index, segment in parts {
    let spelling = segment.to_owned()
    let id = spelling.to_lower()
    let leaf = index == parts.length() - 1
    let dir = directory || !leaf
    let entry = match current.get(id) {
      Some(node) => {
        if node.segment != spelling ||
          node.directory != dir ||
          (leaf && node.explicit) {
          raise @cli.CliError::Invalid("conflicting npm tar path: " + path)
        }
        if leaf {
          node.explicit = true
        }
        node
      }
      None => {
        if path_count.val >= 65536 {
          raise @cli.CliError::Invalid(
            "npm archive contains too many path components",
          )
        }
        path_count.val += 1
        let node = {
          segment: spelling,
          explicit: leaf,
          directory: dir,
          children: Map([]),
        }
        current[id] = node
        node
      }
    }
    current = entry.children
  }
}

///|
fn bundle_validate_archive_path(path : String) -> Unit raise @cli.CliError {
  if @bundle_path.portable_path_error(path) is Some(message) {
    raise @cli.CliError::Invalid(
      "npm archive entry " + Json::string(path).stringify() + " " + message,
    )
  }
}
