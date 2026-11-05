///|
/// component 适配层。解析/验证用 `wasm_component`，打印用 `moonrockz/wit`。
pub fn validate_component(data : Bytes) -> Unit raise @cli.CliError {
  let component = @component.parse_component(data) catch {
    e => raise @cli.CliError::Invalid("parse: " + e.to_string())
  }
  @component_validator.validate_component(component) catch {
    e => raise @cli.CliError::Invalid(e.to_string())
  }
}

///|
/// 组件可能包含多个 core module，输出时用 `; ---- name ----` 分隔。
pub fn component_to_wat(data : Bytes) -> String raise @cli.CliError {
  match @decompiler.print_binary(data) {
    Ok(documents) => {
      let out = StringBuilder()
      for document in documents.documents {
        if !out.is_empty() {
          out.write_string("\n")
        }
        out.write_string("; ---- " + document.name + " ----\n")
        out.write_string(document.text)
        if !document.text.has_suffix("\n") {
          out.write_string("\n")
        }
      }
      out.to_string()
    }
    Err(diagnostics) => {
      let out = StringBuilder()
      for diagnostic in diagnostics {
        out.write_string(diagnostic.message)
        out.write_string("\n")
      }
      raise @cli.CliError::Invalid("decompile: " + out.to_string())
    }
  }
}

///|
pub fn component_wat_to_binary(text : String) -> Bytes raise @cli.CliError {
  @component_text.parse_component_wat(text) catch {
    e => raise @cli.CliError::Invalid("parse: " + e.to_string())
  }
}

///|
pub fn component_to_wit(data : Bytes) -> String raise @cli.CliError {
  let wit_pkg = @component_wit.decode_wit_package_from_component(data) catch {
    e =>
      raise @cli.CliError::Unsupported(
        "component has no WIT package: " + e.to_string(),
      )
  }
  @component_wit.format_package(wit_pkg)
}
