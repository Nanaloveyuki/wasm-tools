///|
fn facts(bytes : Int32) -> Facts {
  { bytes, sha256: "abc", sections: [], imports: [], custom_sections: [], }
}

///|
fn empty_rules() -> Rules {
  {
    max_bytes: None,
    max_growth_bytes: None,
    max_growth_percent: None,
    section_budgets: Map([]),
    allowed_imports: None,
    required_custom_sections: [],
    forbidden_custom_sections: [],
  }
}

///|
test "config parses optional fields and defaults" {
  let config = parse_config(
    (
      #|{"format_version":1,"artifacts":[{"id":"release-1","input":"app.wasm","rules":{}}]}
    ),
  ) catch {
    error => fail(error.message())
  }
  inspect(config.format_version, content="1")
  inspect(config.artifacts.length(), content="1")
  inspect(
    config.artifacts[0].process.strip_custom_sections.is_empty(),
    content="true",
  )
  inspect(config.artifacts[0].process.optimize is None, content="true")
  inspect(config.artifacts[0].baseline is None, content="true")
  inspect(config.artifacts[0].rules.allowed_imports is None, content="true")
  inspect(config.artifacts[0].rules.section_budgets.is_empty(), content="true")
}

///|
test "config rejects unknown and duplicate JSON keys" {
  let unknown = parse_config(
    (
      #|{"format_version":1,"extra":true,"artifacts":[{"id":"app","input":"app.wasm","rules":{}}]}
    ),
  ) catch {
    error => {
      inspect(error.message().contains("unknown key"), content="true")
      return
    }
  }
  ignore(unknown)
  fail("unknown config key was accepted")
}

///|
test "config rejects duplicate JSON keys, ids and Windows device ids" {
  let duplicate_key = parse_config(
    (
      #|{"format_version":1,"format_version":1,"artifacts":[{"id":"app","input":"app.wasm","rules":{}}]}
    ),
  ) catch {
    error => {
      inspect(error.message().contains("invalid JSON"), content="true")
      let duplicate_id = parse_config(
        (
          #|{"format_version":1,"artifacts":[{"id":"App","input":"a.wasm","rules":{}},{"id":"app","input":"b.wasm","rules":{}}]}
        ),
      ) catch {
        duplicate_error => {
          inspect(
            duplicate_error.message().contains("duplicate artifact id"),
            content="true",
          )
          let reserved = parse_config(
            (
              #|{"format_version":1,"artifacts":[{"id":"COM1","input":"a.wasm","rules":{}}]}
            ),
          ) catch {
            reserved_error => {
              inspect(
                reserved_error.message().contains("reserved Windows"),
                content="true",
              )
              return
            }
          }
          ignore(reserved)
          fail("reserved device id was accepted")
        }
      }
      ignore(duplicate_id)
      fail("duplicate artifact id was accepted")
    }
  }
  ignore(duplicate_key)
  fail("duplicate JSON key was accepted")
}

///|
test "section budget names are validated against core labels" {
  let invalid = parse_config(
    (
      #|{"format_version":1,"artifacts":[{"id":"app","input":"a.wasm","rules":{"section_budgets":{"cod":20}}}]}
    ),
  ) catch {
    error => {
      inspect(
        error.message().contains("unsupported section label"),
        content="true",
      )
      let valid = parse_config(
        (
          #|{"format_version":1,"artifacts":[{"id":"app","input":"a.wasm","rules":{"section_budgets":{"code":20,"custom:":10}}}]}
        ),
      ) catch {
        valid_error => fail(valid_error.message())
      }
      inspect(
        valid.artifacts[0].rules.section_budgets.contains("custom:"),
        content="true",
      )
      return
    }
  }
  ignore(invalid)
  fail("misspelled section label was accepted")
}

///|
test "empty import and custom section names are valid exact values" {
  let config = parse_config(
    (
      #|{"format_version":1,"artifacts":[{"id":"app","input":"a.wasm","rules":{"allowed_imports":[{"module":"","name":""}],"required_custom_sections":[""],"forbidden_custom_sections":[]}}]}
    ),
  ) catch {
    error => fail(error.message())
  }
  inspect(
    config.artifacts[0].rules.allowed_imports.unwrap_or([])[0].import_module,
    content="",
  )
  let strip_config = parse_config(
    (
      #|{"format_version":1,"artifacts":[{"id":"strip","input":"a.wasm","rules":{},"process":{"strip_custom_sections":[""]}}]}
    ),
  ) catch {
    error => fail(error.message())
  }
  inspect(
    strip_config.artifacts[0].process.strip_custom_sections[0],
    content="",
  )
  let facts = {
    ..facts(1),
    imports: [{ import_module: "", name: "", }],
    custom_sections: [""],
  }
  inspect(
    evaluate(config.artifacts[0].rules, facts, None).is_empty(),
    content="true",
  )
}

///|
test "config rejects bad versions ranges and conflicting custom section rules" {
  let invalid = parse_config(
    (
      #|{"format_version":1,"artifacts":[{"id":"app","input":"a.wasm","rules":{"max_bytes":-1}}]}
    ),
  ) catch {
    error => {
      inspect(error.message().contains("32-bit integer"), content="true")
      let conflict = parse_config(
        (
          #|{"format_version":1,"artifacts":[{"id":"app","input":"a.wasm","rules":{"required_custom_sections":["name"],"forbidden_custom_sections":["name"]}}]}
        ),
      ) catch {
        conflict_error => {
          inspect(
            conflict_error.message().contains("both requires and forbids"),
            content="true",
          )
          return
        }
      }
      ignore(conflict)
      fail("conflicting custom section rules were accepted")
    }
  }
  ignore(invalid)
  fail("negative size limit was accepted")
}

///|
test "growth budgets compare exact integer cross products and require a baseline" {
  let rules = {
    ..empty_rules(),
    max_growth_bytes: Some(20),
    max_growth_percent: Some(10),
  }
  inspect(
    evaluate(rules, facts(110), Some(facts(100))).is_empty(),
    content="true",
  )
  let over = evaluate(rules, facts(111), Some(facts(100)))
  inspect(over.length(), content="1")
  inspect(over[0].rule, content="max_growth_percent")
  let missing = evaluate(rules, facts(1), None)
  inspect(missing.length(), content="1")
  inspect(missing[0].rule, content="baseline_required")
  let zero_baseline = evaluate(
    { ..empty_rules(), max_growth_percent: Some(0), },
    facts(1),
    Some(facts(0)),
  )
  inspect(zero_baseline[0].rule, content="max_growth_percent")
  inspect(
    evaluate(
      { ..empty_rules(), max_growth_percent: Some(0), },
      facts(0),
      Some(facts(0)),
    ).is_empty(),
    content="true",
  )
}

///|
test "section budgets aggregate duplicate section names" {
  let rules = { ..empty_rules(), section_budgets: Map([("code", 11)]), }
  let artifact = {
    ..facts(12),
    sections: [{ name: "code", bytes: 5, }, { name: "code", bytes: 7, }],
  }
  let findings = evaluate(rules, artifact, None)
  inspect(findings.length(), content="1")
  inspect(findings[0].rule, content="section_budget:code")
  inspect(findings[0].actual.stringify(), content="12")
}

///|
test "section budget findings are sorted by label" {
  let rules = {
    ..empty_rules(),
    section_budgets: Map([("data", 0), ("code", 0)]),
  }
  let findings = evaluate(
    rules,
    {
      ..facts(1),
      sections: [{ name: "data", bytes: 1, }, { name: "code", bytes: 1, }],
    },
    None,
  )
  inspect(findings[0].rule, content="section_budget:code")
  inspect(findings[1].rule, content="section_budget:data")
}

///|
test "import allowlist uses exact module and name pairs" {
  let rules = {
    ..empty_rules(),
    allowed_imports: Some([{ import_module: "env", name: "log", }]),
  }
  let matching = {
    ..facts(1),
    imports: [{ import_module: "env", name: "log", }],
  }
  inspect(evaluate(rules, matching, None).is_empty(), content="true")
  let denied = {
    ..facts(1),
    imports: [{ import_module: "other", name: "log", }],
  }
  let findings = evaluate(rules, denied, None)
  inspect(findings.length(), content="1")
  inspect(findings[0].rule, content="allowed_imports")
  inspect(
    evaluate({ ..empty_rules(), allowed_imports: Some([]), }, matching, None).length(),
    content="1",
  )
}

///|
test "required and forbidden custom section rules are enforced" {
  let rules = {
    ..empty_rules(),
    required_custom_sections: ["producers"],
    forbidden_custom_sections: ["debug_info"],
  }
  let findings = evaluate(
    rules,
    { ..facts(1), custom_sections: ["debug_info"], },
    None,
  )
  inspect(findings.length(), content="2")
  inspect(findings[0].rule, content="required_custom_section:producers")
  inspect(findings[1].rule, content="forbidden_custom_section:debug_info")
}
