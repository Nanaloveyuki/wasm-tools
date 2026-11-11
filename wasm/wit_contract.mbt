///|
pub fn wit_world_snapshot(
  data : Bytes,
  world_name : String,
) -> @contract.WitSnapshot raise @cli.CliError {
  let text = @utf8.decode(data.exact_view()) catch {
    _ => raise @cli.CliError::Invalid("WIT source is not valid UTF-8")
  }
  let parsed = @wit_parser.parse(
    text,
    features=@wit_parser.Features::reference(),
  )
  if !parsed.is_valid() {
    let details = parsed.diagnostics
      .map(diagnostic => diagnostic.message)
      .join("\n")
    raise @cli.CliError::Invalid("WIT parse failed:\n" + details)
  }
  let verified = match
    @wit_verifier.verify(
      parsed,
      source_id="input.wit",
      source=text,
      semantic_features=@wit_verifier.SemanticFeatures::all(),
    ) {
    Ok(value) => value
    Err(diagnostics) => {
      let details = diagnostics
        .map(diagnostic => diagnostic.code + ": " + diagnostic.message)
        .join("\n")
      raise @cli.CliError::Invalid("WIT verification failed:\n" + details)
    }
  }
  let world = match verified.select_world(name=Some(world_name)) {
    Ok(value) => value
    Err(diagnostics) => {
      let details = diagnostics
        .map(diagnostic => diagnostic.code + ": " + diagnostic.message)
        .join("\n")
      raise @cli.CliError::Invalid("WIT world selection failed:\n" + details)
    }
  }
  match world.stability {
    @wit_verifier.Unstable(feature, _) =>
      raise @cli.CliError::Unsupported(
        "feature-gated WIT world requires an explicit feature selection: " +
        feature,
      )
    _ => ()
  }
  build_wit_snapshot(verified, world)
}

///|
fn build_wit_snapshot(
  verified : @wit_verifier.Verified,
  world : @wit_verifier.ResolvedWorld,
) -> @contract.WitSnapshot raise @cli.CliError {
  let types : Map[Int32, @wit_verifier.ResolvedType] = Map([])
  for type_ in verified.types() {
    types[type_.id] = type_
  }
  let functions : Map[Int32, @wit_verifier.ResolvedFunction] = Map([])
  for function in verified.functions() {
    functions[function.id] = function
  }
  let interfaces : Map[Int32, @wit_verifier.ResolvedInterface] = Map([])
  let scope_names : Map[Int32, String] = Map([])
  for interface_ in verified.interfaces() {
    interfaces[interface_.id] = interface_
    scope_names[interface_.id] = package_identity_key(
        interface_.package_identity,
      ) +
      "/" +
      interface_.name.unwrap_or("inline")
  }
  for resolved_world in verified.worlds() {
    scope_names[resolved_world.id] = package_identity_key(
        resolved_world.package_identity,
      ) +
      "/world:" +
      resolved_world.name
  }
  for
    (direction, items) in [("import", world.imports), ("export", world.exports)] {
    for item in items {
      if item.kind is @wit_verifier.Interface(interface_id) &&
        interfaces.get(interface_id) is Some(interface_) &&
        interface_.name is None {
        scope_names[interface_id] = package_identity_key(world.package_identity) +
          "/" +
          direction +
          ":" +
          normalize_wit_name(item.name)
      }
    }
  }
  let imports = wit_entries(
    world.imports,
    functions,
    interfaces,
    types,
    scope_names,
  )
  let exports = wit_entries(
    world.exports,
    functions,
    interfaces,
    types,
    scope_names,
  )
  @contract.WitSnapshot::new(
    world.package_identity.namespace_name,
    world.package_identity.name,
    world.package_identity.version,
    world.name,
    imports,
    exports,
  )
}

///|
fn wit_entries(
  items : ReadOnlyArray[@wit_verifier.WorldItem],
  functions : Map[Int32, @wit_verifier.ResolvedFunction],
  interfaces : Map[Int32, @wit_verifier.ResolvedInterface],
  types : Map[Int32, @wit_verifier.ResolvedType],
  scope_names : Map[Int32, String],
) -> Array[@contract.WitEntry] raise @cli.CliError {
  let entries : Array[@contract.WitEntry] = []
  for item in items {
    let (kind, signature) = match item.kind {
      @wit_verifier.Interface(id) =>
        match interfaces.get(id) {
          Some(interface_) =>
            (
              "interface",
              interface_signature(interface_, types, scope_names) catch {
                @cli.CliError::Unsupported(reason) => "unknown:" + reason
                error => raise error
              },
            )
          None =>
            raise @cli.CliError::Unsupported(
              "WIT interface reference is not present in the verified type graph",
            )
        }
      @wit_verifier.Function(id) =>
        match functions.get(id) {
          Some(function) =>
            (
              "function",
              wit_function_signature(function, types, scope_names) catch {
                @cli.CliError::Unsupported(reason) => "unknown:" + reason
                error => raise error
              },
            )
          None =>
            raise @cli.CliError::Unsupported(
              "WIT function reference is not present in the verified function graph",
            )
        }
      @wit_verifier.Type(id) =>
        (
          "type",
          wit_type_key(id, types, scope_names, 0, Map([])) catch {
            @cli.CliError::Unsupported(reason) => "unknown:" + reason
            error => raise error
          },
        )
    }
    let signature = match item.stability {
      @wit_verifier.Unstable(feature, _) =>
        "unknown:feature-gated WIT world item: " + feature
      _ => signature
    }
    entries.push({ name: normalize_wit_name(item.name), kind, signature, })
  }
  entries
}

///|
fn interface_signature(
  interface_ : @wit_verifier.ResolvedInterface,
  types : Map[Int32, @wit_verifier.ResolvedType],
  scope_names : Map[Int32, String],
) -> String raise @cli.CliError {
  ensure_wit_stability(interface_.stability)
  let alias_targets : Map[Int32, Int32] = Map([])
  let members : Array[(String, String)] = []
  for item in interface_.types {
    members.push(
      (
        "type:" + item.name,
        wit_type_key(item.ty, types, scope_names, 0, alias_targets),
      ),
    )
  }
  for function_ref in interface_.functions {
    members.push(
      (
        "function:" + function_ref.name,
        wit_function_signature(function_ref, types, scope_names),
      ),
    )
  }
  members.sort_by(fn(left, right) { left.0.lexical_compare(right.0) })
  "interface{" + members.map(item => wit_pair(item.0, item.1)).join("") + "}"
}

///|
fn wit_function_signature(
  function : @wit_verifier.ResolvedFunction,
  types : Map[Int32, @wit_verifier.ResolvedType],
  scope_names : Map[Int32, String],
) -> String raise @cli.CliError {
  ensure_wit_stability(function.stability)
  let alias_targets : Map[Int32, Int32] = Map([])
  let out = StringBuilder()
  out.write_string("fn[")
  for param in function.params {
    out.write_string(
      wit_type_key(param.ty, types, scope_names, 0, alias_targets),
    )
    out.write_char(';')
  }
  out.write_string("]->")
  match function.result {
    Some(result) =>
      out.write_string(
        wit_type_key(result, types, scope_names, 0, alias_targets),
      )
    None => out.write_string("unit")
  }
  out.write_string(if function.asynchronous { ";async" } else { ";sync" })
  out.write_string(
    match function.kind {
      @wit_verifier.Freestanding => ";free"
      @wit_verifier.Method(resource) =>
        ";method:" + wit_resource_key(resource, types, scope_names)
      @wit_verifier.Static(resource) =>
        ";static:" + wit_resource_key(resource, types, scope_names)
      @wit_verifier.Constructor(resource) =>
        ";constructor:" + wit_resource_key(resource, types, scope_names)
    },
  )
  out.write_string(
    match function.flavor {
      @wit_verifier.Plain => ";plain"
      @wit_verifier.Getter => ";getter"
      @wit_verifier.Setter => ";setter"
    },
  )
  out.to_string()
}

///|
fn wit_type_key(
  id : Int32,
  types : Map[Int32, @wit_verifier.ResolvedType],
  scope_names : Map[Int32, String],
  depth : Int32,
  alias_targets : Map[Int32, Int32],
) -> String raise @cli.CliError {
  if depth > 256 {
    raise @cli.CliError::Unsupported(
      "WIT type graph exceeds the supported nesting depth",
    )
  }
  let id = resolve_wit_alias(id, types, alias_targets)
  guard types.get(id) is Some(type_) else {
    raise @cli.CliError::Unsupported(
      "WIT type reference is missing from the verified type graph",
    )
  }
  ensure_wit_stability(type_.stability)
  match type_.kind {
    @wit_verifier.Scalar(name) => "scalar:" + name
    @wit_verifier.Resource => wit_resource_key(id, types, scope_names)
    @wit_verifier.Own(resource) =>
      "own:" + wit_resource_key(resource, types, scope_names)
    @wit_verifier.Borrow(resource) =>
      "borrow:" + wit_resource_key(resource, types, scope_names)
    @wit_verifier.Alias(target) =>
      wit_type_key(target, types, scope_names, depth, alias_targets)
    @wit_verifier.List(element, length) =>
      "list:" +
      length.map(v => v.to_string()).unwrap_or("*") +
      "<" +
      wit_type_key(element, types, scope_names, depth + 1, alias_targets) +
      ">"
    @wit_verifier.Tuple(elements) =>
      "tuple[" +
      elements
      .map(element => {
        wit_type_key(element, types, scope_names, depth + 1, alias_targets)
      })
      .join(";") +
      "]"
    @wit_verifier.Option(payload) =>
      "option<" +
      wit_type_key(payload, types, scope_names, depth + 1, alias_targets) +
      ">"
    @wit_verifier.Result(ok, error) =>
      "result<" +
      optional_wit_type(ok, types, scope_names, depth, alias_targets) +
      "," +
      optional_wit_type(error, types, scope_names, depth, alias_targets) +
      ">"
    @wit_verifier.Future(payload) =>
      "future<" +
      optional_wit_type(payload, types, scope_names, depth, alias_targets) +
      ">"
    @wit_verifier.Stream(payload) =>
      "stream<" +
      optional_wit_type(payload, types, scope_names, depth, alias_targets) +
      ">"
    @wit_verifier.Map(key, value) =>
      "map<" +
      wit_type_key(key, types, scope_names, depth + 1, alias_targets) +
      "," +
      wit_type_key(value, types, scope_names, depth + 1, alias_targets) +
      ">"
    @wit_verifier.Record(fields) =>
      "record{" +
      fields
      .map(field => {
        wit_pair(
          field.name,
          wit_type_key(field.ty, types, scope_names, depth + 1, alias_targets),
        )
      })
      .join("") +
      "}"
    @wit_verifier.Flags(names) => "flags[" + names.join(";") + "]"
    @wit_verifier.Enum(names) => "enum[" + names.join(";") + "]"
    @wit_verifier.Variant(cases) =>
      "variant[" +
      cases
      .map(case_ => {
        wit_pair(
          case_.name,
          case_.payload
          .map(payload => {
            wit_type_key(payload, types, scope_names, depth + 1, alias_targets)
          })
          .unwrap_or("unit"),
        )
      })
      .join("") +
      "]"
  }
}

///|
fn resolve_wit_alias(
  id : Int32,
  types : Map[Int32, @wit_verifier.ResolvedType],
  alias_targets : Map[Int32, Int32],
) -> Int32 raise @cli.CliError {
  let path : Array[Int32] = []
  let mut current = id
  let mut steps = 0
  while true {
    match alias_targets.get(current) {
      Some(target) => {
        current = target
        break
      }
      None => ()
    }
    guard types.get(current) is Some(type_) else {
      raise @cli.CliError::Unsupported(
        "WIT type reference is missing from the verified type graph",
      )
    }
    ensure_wit_stability(type_.stability)
    match type_.kind {
      @wit_verifier.Alias(target) => {
        path.push(current)
        current = target
        steps += 1
        if steps > 65536 {
          raise @cli.CliError::Unsupported(
            "WIT alias chain exceeds the supported work limit",
          )
        }
      }
      _ => break
    }
  }
  for alias_id in path {
    alias_targets[alias_id] = current
  }
  current
}

///|
fn ensure_wit_stability(
  stability : @wit_verifier.Stability,
) -> Unit raise @cli.CliError {
  match stability {
    @wit_verifier.Unstable(feature, _) =>
      raise @cli.CliError::Unsupported(
        "feature-gated WIT structure requires an explicit feature selection: " +
        feature,
      )
    _ => ()
  }
}

///|
fn optional_wit_type(
  id : Int32?,
  types : Map[Int32, @wit_verifier.ResolvedType],
  scope_names : Map[Int32, String],
  depth : Int32,
  alias_targets : Map[Int32, Int32],
) -> String raise @cli.CliError {
  match id {
    Some(value) =>
      wit_type_key(value, types, scope_names, depth + 1, alias_targets)
    None => "unit"
  }
}

///|
fn wit_resource_key(
  id : Int32,
  types : Map[Int32, @wit_verifier.ResolvedType],
  scope_names : Map[Int32, String],
) -> String raise @cli.CliError {
  guard types.get(id) is Some(type_) else {
    raise @cli.CliError::Unsupported(
      "WIT resource reference is missing from the verified type graph",
    )
  }
  guard type_.kind is @wit_verifier.Resource else {
    raise @cli.CliError::Unsupported(
      "WIT handle does not refer to a resource type",
    )
  }
  let scope = match scope_names.get(type_.scope) {
    Some(value) => value
    None =>
      raise @cli.CliError::Unsupported(
        "resource scope cannot be assigned a stable WIT identity",
      )
  }
  scope + "#" + type_.name.unwrap_or("resource")
}

///|
fn package_identity_key(identity : @wit_verifier.PackageIdentity) -> String {
  identity.namespace_name + ":" + identity.name
}

///|
fn normalize_wit_name(name : String) -> String {
  let parts = name.split("@").map(StringView::to_owned).to_array()
  if parts.length() > 1 {
    let base = StringBuilder()
    for i in 0..<(parts.length() - 1) {
      if i > 0 {
        base.write_char('@')
      }
      base.write_string(parts[i])
    }
    base.to_string()
  } else {
    name
  }
}

///|
fn wit_pair(name : String, value : String) -> String {
  name.length().to_string() +
  ":" +
  name +
  value.length().to_string() +
  ":" +
  value
}
