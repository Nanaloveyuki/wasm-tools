///|
/// 输入类型判定。只依赖魔数与 header 的 version/layer 字段，不做完整解析。
///
/// core module 的 header 是 `\0asm` + 01 00 00 00；
/// component 的 header 是 `\0asm` + 0d 00 01 00（version 13、layer 1）。
pub enum InputKind {
  CoreModule
  Component
}

///|
pub fn detect_kind(data : Bytes) -> InputKind raise @cli.CliError {
  if data.length() < 8 {
    raise @cli.CliError::Invalid("input is shorter than the 8-byte wasm header")
  }
  if data[0] != b'\x00' ||
    data[1] != b'a' ||
    data[2] != b's' ||
    data[3] != b'm' {
    raise @cli.CliError::Invalid("missing wasm magic header")
  }
  let version = data[4].to_int() | (data[5].to_int() << 8)
  let layer = data[6].to_int() | (data[7].to_int() << 8)
  if version == 1 && layer == 0 {
    CoreModule
  } else if version == 0x0d && layer == 1 {
    Component
  } else {
    raise @cli.CliError::Invalid(
      "unsupported wasm header (version " +
      version.to_string() +
      ", layer " +
      layer.to_string() +
      ")",
    )
  }
}

///|
/// 组件有自己的 section id 空间；在实现组件感知的扫描前，明确拒绝而不是输出错误标签。
pub fn reject_component(data : Bytes, command : String) -> Unit raise @cli.CliError {
  match detect_kind(data) {
    Component => raise @cli.CliError::Unsupported(command + ": component binaries are not supported yet")
    CoreModule => ()
  }
}

///|
pub fn InputKind::is_component(self : InputKind) -> Bool {
  match self {
    Component => true
    CoreModule => false
  }
}

///|
/// section id 的含义随 core/component 不同；未知 id 保留数字，避免误标。
pub fn section_name(kind : InputKind, id : Int) -> String {
  match kind {
    CoreModule =>
      match id {
        0 => "custom"
        1 => "type"
        2 => "import"
        3 => "function"
        4 => "table"
        5 => "memory"
        6 => "global"
        7 => "export"
        8 => "start"
        9 => "element"
        10 => "code"
        11 => "data"
        12 => "data-count"
        13 => "tag"
        _ => "unknown(" + id.to_string() + ")"
      }
    Component =>
      match id {
        0 => "custom"
        1 => "core-module"
        2 => "core-instance"
        3 => "core-type"
        4 => "component"
        5 => "instance"
        6 => "alias"
        7 => "type"
        8 => "canon"
        9 => "start"
        10 => "import"
        11 => "export"
        _ => "unknown(" + id.to_string() + ")"
      }
  }
}
