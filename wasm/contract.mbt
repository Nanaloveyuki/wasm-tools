///|
pub fn contract_snapshot(
  data : Bytes,
) -> @contract.Snapshot raise @cli.CliError {
  reject_component(data, "contract")
  let parsed_module = @core_parser.parse_module(data) catch {
    e => raise @cli.CliError::Invalid("parse: " + e.to_string())
  }
  @core_validator.validate_module(parsed_module) catch {
    e =>
      raise @cli.CliError::Invalid(@core_validator.format_validation_error(e))
  }
  let imports : Array[@contract.Entry] = []
  for imported in parsed_module.imports {
    imports.push(import_entry(parsed_module, imported))
  }
  let exports : Array[@contract.Entry] = []
  for exported in parsed_module.exports {
    exports.push(export_entry(parsed_module, exported))
  }
  @contract.Snapshot::new(imports, exports)
}

///|
fn import_entry(
  parsed_module : @core_types.Module,
  imported : @core_types.Import,
) -> @contract.Entry {
  let (kind, type_) = match imported.desc {
    @core_types.ImportDesc::Func(type_idx) =>
      (@contract.ExternalKind::Function, function_type(parsed_module, type_idx))
    @core_types.ImportDesc::Table(table) =>
      (@contract.ExternalKind::Table, table_type(table))
    @core_types.ImportDesc::Memory(memory) =>
      (@contract.ExternalKind::Memory, memory_type(memory))
    @core_types.ImportDesc::Global(global) =>
      (@contract.ExternalKind::Global, global_type(global))
    @core_types.ImportDesc::Tag(type_idx) =>
      (@contract.ExternalKind::Tag, tag_type(parsed_module, type_idx))
  }
  { import_module: Some(imported.mod_name), name: imported.name, kind, type_, }
}

///|
fn export_entry(
  parsed_module : @core_types.Module,
  exported : @core_types.Export,
) -> @contract.Entry {
  let (kind, type_) = match exported.desc {
    @core_types.ExportDesc::Func(index) =>
      (
        @contract.ExternalKind::Function,
        match function_type_index(parsed_module, index) {
          Some(type_idx) => function_type(parsed_module, type_idx)
          None =>
            @contract.ExternalType::Unsupported(
              "function index is out of range",
            )
        },
      )
    @core_types.ExportDesc::Table(index) =>
      (
        @contract.ExternalKind::Table,
        match table_type_at(parsed_module, index) {
          Some(value) => table_type(value)
          None =>
            @contract.ExternalType::Unsupported("table index is out of range")
        },
      )
    @core_types.ExportDesc::Memory(index) =>
      (
        @contract.ExternalKind::Memory,
        match memory_type_at(parsed_module, index) {
          Some(value) => memory_type(value)
          None =>
            @contract.ExternalType::Unsupported("memory index is out of range")
        },
      )
    @core_types.ExportDesc::Global(index) =>
      (
        @contract.ExternalKind::Global,
        match global_type_at(parsed_module, index) {
          Some(value) => global_type(value)
          None =>
            @contract.ExternalType::Unsupported("global index is out of range")
        },
      )
    @core_types.ExportDesc::Tag(index) =>
      (
        @contract.ExternalKind::Tag,
        match tag_type_index(parsed_module, index) {
          Some(type_idx) => tag_type(parsed_module, type_idx)
          None =>
            @contract.ExternalType::Unsupported("tag index is out of range")
        },
      )
  }
  { import_module: None, name: exported.name, kind, type_, }
}

///|
fn function_type_index(
  parsed_module : @core_types.Module,
  index : Int32,
) -> Int32? {
  let mut imported_functions = 0
  for imported in parsed_module.imports {
    match imported.desc {
      @core_types.ImportDesc::Func(type_idx) => {
        if imported_functions == index {
          return Some(type_idx)
        }
        imported_functions = imported_functions + 1
      }
      _ => ()
    }
  }
  let local_index = index - imported_functions
  if local_index >= 0 && local_index < parsed_module.funcs.length() {
    Some(parsed_module.funcs[local_index])
  } else {
    None
  }
}

///|
fn table_type_at(
  parsed_module : @core_types.Module,
  index : Int32,
) -> @core_types.TableType? {
  let mut imported_tables = 0
  for imported in parsed_module.imports {
    match imported.desc {
      @core_types.ImportDesc::Table(type_) => {
        if imported_tables == index {
          return Some(type_)
        }
        imported_tables = imported_tables + 1
      }
      _ => ()
    }
  }
  let local_index = index - imported_tables
  if local_index >= 0 && local_index < parsed_module.tables.length() {
    Some(parsed_module.tables[local_index].type_)
  } else {
    None
  }
}

///|
fn memory_type_at(
  parsed_module : @core_types.Module,
  index : Int32,
) -> @core_types.MemoryType? {
  let mut imported_memories = 0
  for imported in parsed_module.imports {
    match imported.desc {
      @core_types.ImportDesc::Memory(type_) => {
        if imported_memories == index {
          return Some(type_)
        }
        imported_memories = imported_memories + 1
      }
      _ => ()
    }
  }
  let local_index = index - imported_memories
  if local_index >= 0 && local_index < parsed_module.memories.length() {
    Some(parsed_module.memories[local_index])
  } else {
    None
  }
}

///|
fn global_type_at(
  parsed_module : @core_types.Module,
  index : Int32,
) -> @core_types.GlobalType? {
  let mut imported_globals = 0
  for imported in parsed_module.imports {
    match imported.desc {
      @core_types.ImportDesc::Global(type_) => {
        if imported_globals == index {
          return Some(type_)
        }
        imported_globals = imported_globals + 1
      }
      _ => ()
    }
  }
  let local_index = index - imported_globals
  if local_index >= 0 && local_index < parsed_module.globals.length() {
    Some(parsed_module.globals[local_index].type_)
  } else {
    None
  }
}

///|
fn tag_type_index(parsed_module : @core_types.Module, index : Int32) -> Int32? {
  let mut imported_tags = 0
  for imported in parsed_module.imports {
    match imported.desc {
      @core_types.ImportDesc::Tag(type_idx) => {
        if imported_tags == index {
          return Some(type_idx)
        }
        imported_tags = imported_tags + 1
      }
      _ => ()
    }
  }
  let local_index = index - imported_tags
  if local_index >= 0 && local_index < parsed_module.tags.length() {
    Some(parsed_module.tags[local_index].type_idx)
  } else {
    None
  }
}

///|
fn function_type(
  parsed_module : @core_types.Module,
  type_idx : Int32,
) -> @contract.ExternalType {
  match parsed_module.func_type_at(type_idx) {
    Some(type_) => {
      let subtype = parsed_module.types[type_idx]
      if !subtype.final_ || !subtype.supertypes.is_empty() {
        return @contract.ExternalType::Unsupported(
          "function signature uses a declared subtype",
        )
      }
      let params = value_types(type_.params)
      let results = value_types(type_.results)
      match (params, results) {
        (Some(params), Some(results)) =>
          @contract.ExternalType::Function(params, results)
        _ =>
          @contract.ExternalType::Unsupported(
            "function signature contains typed reference types",
          )
      }
    }
    None =>
      @contract.ExternalType::Unsupported(
        "type index is out of range or is not a function type",
      )
  }
}

///|
fn tag_type(
  parsed_module : @core_types.Module,
  type_idx : Int32,
) -> @contract.ExternalType {
  match parsed_module.func_type_at(type_idx) {
    Some(type_) => {
      let subtype = parsed_module.types[type_idx]
      if !subtype.final_ || !subtype.supertypes.is_empty() {
        return @contract.ExternalType::Unsupported(
          "tag signature uses a declared subtype",
        )
      }
      if type_.results.is_empty() {
        match value_types(type_.params) {
          Some(params) => @contract.ExternalType::Tag(params)
          None =>
            @contract.ExternalType::Unsupported(
              "tag signature contains typed reference types",
            )
        }
      } else {
        @contract.ExternalType::Unsupported("tag signature has results")
      }
    }
    None =>
      @contract.ExternalType::Unsupported(
        "tag type index is out of range or is not a function type",
      )
  }
}

///|
fn value_types(values : ReadOnlyArray[@core_types.ValueType]) -> Array[String]? {
  let result : Array[String] = []
  for value in values {
    match value_type_name(value) {
      Some(name) => result.push(name)
      None => return None
    }
  }
  Some(result)
}

///|
fn value_type_name(value : @core_types.ValueType) -> String? {
  match value {
    @core_types.I32 => Some("i32")
    @core_types.I64 => Some("i64")
    @core_types.F32 => Some("f32")
    @core_types.F64 => Some("f64")
    @core_types.V128 => Some("v128")
    @core_types.FuncRef => Some("funcref")
    @core_types.ExternRef => Some("externref")
    @core_types.RefFunc => Some("ref func")
    @core_types.RefExtern => Some("ref extern")
    @core_types.ContRef => Some("contref")
    @core_types.RefCont => Some("ref cont")
    @core_types.NullContRef => Some("null contref")
    @core_types.RefNoCont => Some("ref nocont")
    @core_types.AnyRef => Some("anyref")
    @core_types.ExnRef => Some("exnref")
    @core_types.StructRef => Some("structref")
    @core_types.ArrayRef => Some("arrayref")
    @core_types.RefAny => Some("ref any")
    @core_types.RefEq => Some("ref eq")
    @core_types.RefNullEq => Some("ref null eq")
    @core_types.RefI31 => Some("ref i31")
    @core_types.RefNullI31 => Some("ref null i31")
    @core_types.RefStructAbs => Some("ref struct")
    @core_types.RefArrayAbs => Some("ref array")
    @core_types.RefNone => Some("ref none")
    @core_types.NullRef => Some("nullref")
    @core_types.NullFuncRef => Some("nullfuncref")
    @core_types.NullExnRef => Some("nullexnref")
    @core_types.NullExternRef => Some("nullexternref")
    @core_types.RefFuncTyped(_)
    | @core_types.RefNullFuncTyped(_)
    | @core_types.RefContTyped(_)
    | @core_types.RefNullContTyped(_)
    | @core_types.RefStruct(_)
    | @core_types.RefNullStruct(_)
    | @core_types.RefArray(_)
    | @core_types.RefNullArray(_) => None
  }
}

///|
fn table_type(type_ : @core_types.TableType) -> @contract.ExternalType {
  match value_type_name(type_.elem_type) {
    Some(element) =>
      @contract.ExternalType::Table(
        element,
        limits(type_.limits),
        type_.is_table64,
      )
    None => @contract.ExternalType::Unsupported("table uses a typed reference")
  }
}

///|
fn memory_type(type_ : @core_types.MemoryType) -> @contract.ExternalType {
  @contract.ExternalType::Memory(
    limits(type_.limits),
    type_.is_memory64,
    type_.is_shared,
    type_.page_size_log2,
  )
}

///|
fn global_type(type_ : @core_types.GlobalType) -> @contract.ExternalType {
  match value_type_name(type_.value_type) {
    Some(value_type) =>
      @contract.ExternalType::Global(value_type, type_.mutable)
    None => @contract.ExternalType::Unsupported("global uses a typed reference")
  }
}

///|
fn limits(value : @core_types.Limits) -> @contract.Limits {
  { minimum: value.min, maximum: value.max, }
}
