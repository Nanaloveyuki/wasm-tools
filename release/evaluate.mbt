///|
pub fn evaluate(
  rules : Rules,
  facts : Facts,
  baseline : Facts?,
) -> Array[Finding] {
  let findings : Array[Finding] = []
  if rules.max_bytes is Some(limit) && facts.bytes > limit {
    findings.push({
      rule: "max_bytes",
      message: "artifact size exceeds the absolute byte limit",
      actual: json_int(facts.bytes.to_int64()),
      limit: json_int(limit.to_int64()),
    })
  }

  let has_growth_rules = rules.max_growth_bytes is Some(_) ||
    rules.max_growth_percent is Some(_)
  match (has_growth_rules, baseline) {
    (true, None) =>
      findings.push({
        rule: "baseline_required",
        message: "growth limits require a baseline artifact",
        actual: Json::null(),
        limit: Json::string("baseline facts"),
      })
    (true, Some(before)) => {
      let growth = facts.bytes.to_int64() - before.bytes.to_int64()
      match rules.max_growth_bytes {
        Some(limit) =>
          if growth > limit.to_int64() {
            findings.push({
              rule: "max_growth_bytes",
              message: "artifact byte growth exceeds the configured limit",
              actual: json_int(growth),
              limit: json_int(limit.to_int64()),
            })
          }
        None => ()
      }
      match rules.max_growth_percent {
        Some(limit) =>
          if growth_percent_exceeds(facts.bytes, before.bytes, limit) {
            findings.push({
              rule: "max_growth_percent",
              message: "artifact percentage growth exceeds the configured limit",
              actual: Json::object(
                Map([
                  ("before_bytes", json_int(before.bytes.to_int64())),
                  ("after_bytes", json_int(facts.bytes.to_int64())),
                  ("growth_bytes", json_int(growth)),
                ]),
              ),
              limit: json_int(limit.to_int64()),
            })
          }
        None => ()
      }
    }
    _ => ()
  }

  append_section_budget_findings(
    rules.section_budgets,
    facts.sections,
    findings,
  )
  append_import_findings(rules.allowed_imports, facts.imports, findings)
  append_custom_section_findings(
    rules.required_custom_sections,
    rules.forbidden_custom_sections,
    facts.custom_sections,
    findings,
  )
  findings
}

///|
fn growth_percent_exceeds(
  current : Int32,
  baseline : Int32,
  limit : Int32,
) -> Bool {
  if current <= baseline {
    return false
  }
  if baseline == 0 {
    return true
  }
  (current.to_int64() - baseline.to_int64()) * 100L >
  baseline.to_int64() * limit.to_int64()
}

///|
fn append_section_budget_findings(
  budgets : Map[String, Int32],
  sections : Array[SectionMetric],
  findings : Array[Finding],
) -> Unit {
  let totals : Map[String, Int64] = Map([])
  for section in sections {
    let old = totals.get(section.name).unwrap_or(0L)
    totals.set(section.name, old + section.bytes.to_int64())
  }
  let names : Array[String] = []
  for name in budgets.keys() {
    names.push(name)
  }
  names.sort()
  for name in names {
    let limit = budgets.get(name).unwrap_or(0)
    let actual = totals.get(name).unwrap_or(0L)
    if actual > limit.to_int64() {
      findings.push({
        rule: "section_budget:" + name,
        message: "combined section bytes exceed the configured limit",
        actual: json_int(actual),
        limit: json_int(limit.to_int64()),
      })
    }
  }
}

///|
fn append_import_findings(
  allowed : Array[ImportName]?,
  imports : Array[ImportName],
  findings : Array[Finding],
) -> Unit {
  match allowed {
    None => ()
    Some(allowlist) => {
      let disallowed : Array[Json] = []
      for imported in imports {
        if !allowlist.contains(imported) {
          disallowed.push(
            Json::object(
              Map([
                ("module", Json::string(imported.import_module)),
                ("name", Json::string(imported.name)),
              ]),
            ),
          )
        }
      }
      if !disallowed.is_empty() {
        findings.push({
          rule: "allowed_imports",
          message: "artifact contains imports outside the exact allowlist",
          actual: Json::array(disallowed),
          limit: Json::array(
            allowlist.map(fn(item) {
              Json::object(
                Map([
                  ("module", Json::string(item.import_module)),
                  ("name", Json::string(item.name)),
                ]),
              )
            }),
          ),
        })
      }
    }
  }
}

///|
fn append_custom_section_findings(
  required : Array[String],
  forbidden : Array[String],
  actual : Array[String],
  findings : Array[Finding],
) -> Unit {
  let actual_set : Map[String, Unit] = Map([])
  for name in actual {
    actual_set.set(name, ())
  }
  for name in required {
    if !actual_set.contains(name) {
      findings.push({
        rule: "required_custom_section:" + name,
        message: "required custom section is missing",
        actual: Json::boolean(false),
        limit: Json::boolean(true),
      })
    }
  }
  for name in forbidden {
    if actual_set.contains(name) {
      findings.push({
        rule: "forbidden_custom_section:" + name,
        message: "forbidden custom section is present",
        actual: Json::boolean(true),
        limit: Json::boolean(false),
      })
    }
  }
}

///|
fn json_int(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}
