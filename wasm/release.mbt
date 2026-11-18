///|
pub fn release_facts(data : Bytes) -> @release.Facts raise @cli.CliError {
  reject_component(data, "release")
  let parsed = @core_parser.parse_module(data) catch {
    e => raise @cli.CliError::Invalid("parse: " + e.to_string())
  }
  @core_validator.validate_module(parsed) catch {
    e =>
      raise @cli.CliError::Invalid(@core_validator.format_validation_error(e))
  }
  let sections = scan_sections(data)
  let metrics : Array[@release.SectionMetric] = []
  let custom_sections : Array[String] = []
  for section in sections {
    let name = match section.name {
      Some(name) => {
        custom_sections.push(name)
        "custom:" + name
      }
      None => section_name(CoreModule, section.id)
    }
    metrics.push({
      name,
      bytes: section.payload + section.size - section.start,
    })
  }
  let imports : Array[@release.ImportName] = []
  for entry in parsed.imports {
    imports.push({ import_module: entry.mod_name, name: entry.name, })
  }
  {
    bytes: data.length(),
    sha256: @crypto.bytes_to_hex_string(@crypto.sha256(data)),
    sections: metrics,
    imports,
    custom_sections,
  }
}
