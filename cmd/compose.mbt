///|
pub async fn cmd_compose(args : Array[String]) -> Int raise @cli.CliError {
  let options = @cli.parse_options(args, value_options=["--dep"])
  let dep_values = @cli.take_value(options, "--dep")
  let dce = @cli.take_flag(options, "--dce")
  let best_effort = @cli.take_flag(options, "--best-effort")
  @cli.reject_unknown(options)
  if options.help {
    @cli.write_stdout(
      "Usage: wsm compose [OPTIONS] [FILE.wac]\n\nCompose WebAssembly components from a WAC script.\n  --dep NAME=PATH   Override one package (ns:name=PATH, repeatable)\n  --dce             Drop unused instances and their imports\n  --best-effort     Continue when an import cannot be satisfied\n  -o FILE           Write the component to FILE\n\nPackages resolve to <wac dir>/deps/<ns>/<name>.wasm unless overridden.\n",
    )
    return 0
  }
  let input = options.input.unwrap_or("-")
  let text = if input == "-" {
    let data = @cli.read_input(None)
    try @utf8.decode(data.exact_view()) catch {
      _ => raise @cli.CliError::Invalid("stdin is not valid UTF-8")
    }
  } else {
    let data = @cli.read_input(Some(input))
    try @utf8.decode(data.exact_view()) catch {
      _ => raise @cli.CliError::Invalid(input + " is not valid UTF-8")
    }
  }
  let mut base = "."
  if input != "-" {
    base = match parent_dir(input) {
      Some(dir) => dir
      None => "."
    }
  }
  let compose_options = @wasm.ComposeOptions::new(base)
  compose_options.dce = dce
  compose_options.best_effort = best_effort
  for entry in dep_values {
    match entry.find("=") {
      Some(index) => {
        let name = entry.get_view(start=0, end=index).unwrap_or("").to_owned()
        let path = entry.get_view(start=index + 1).unwrap_or("").to_owned()
        if name.is_empty() || path.is_empty() {
          raise @cli.CliError::Usage("--dep expects NAME=PATH")
        }
        compose_options.deps.set(name, path)
      }
      None => raise @cli.CliError::Usage("--dep expects NAME=PATH")
    }
  }
  let result = @wasm.compose(compose_options, text)
  @cli.write_output(options.output, result)
  0
}

///|
/// WAC 里的相对 deps 路径以脚本所在目录为准；stdin 用当前目录。
fn parent_dir(path : String) -> String? {
  let mut last = -1
  for i, ch in path {
    if ch == '/' || ch == '\\' {
      last = i
    }
  }
  if last < 0 {
    None
  } else if last == 0 {
    Some(path.get_view(start=0, end=1).unwrap_or("/").to_owned())
  } else {
    Some(path.get_view(start=0, end=last).unwrap_or("").to_owned())
  }
}
