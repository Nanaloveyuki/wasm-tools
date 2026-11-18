///|
fn release_markdown(
  mode : String,
  reports : Array[ReleaseArtifactReport],
  output_dir : String?,
) -> String {
  let status = release_status(release_exit_code(reports))
  let out = StringBuilder()
  out.write_string("# WASM 发布报告\n\n")
  out.write_string("- 模式：" + markdown_cell(mode) + "\n")
  out.write_string(
    "- 总体状态：" + markdown_cell(status_label(status)) + "\n",
  )
  match output_dir {
    Some(path) =>
      out.write_string("- 输出目录：" + markdown_cell(path) + "\n")
    None => ()
  }
  out.write_string(
    "\n变化按基线计算；未配置基线时按输入产物计算。\n\n" +
    "| Artifact | 输入 | 输入字节 | 最终字节 | 基线字节 | 变化 | 状态 |\n",
  )
  out.write_string("| --- | --- | ---: | ---: | ---: | ---: | --- |\n")
  for report in reports {
    let before_bytes = markdown_optional_bytes(report.before)
    let after_bytes = markdown_optional_bytes(report.after)
    let baseline_facts = release_baseline_facts(report)
    let baseline_bytes = markdown_optional_bytes(report.baseline)
    let delta = markdown_delta(baseline_facts, report.after)
    out.write_string(
      "| " +
      markdown_cell(report.id) +
      " | " +
      markdown_cell(report.input) +
      " | " +
      before_bytes +
      " | " +
      after_bytes +
      " | " +
      baseline_bytes +
      " | " +
      delta +
      " | " +
      markdown_cell(status_label(release_status(report.exit_code))) +
      " |\n",
    )
  }

  for report in reports {
    out.write_string("\n## " + markdown_cell(report.id) + "\n\n")
    if report.error is Some(error) {
      out.write_string("- 错误：" + markdown_cell(error) + "\n")
    }
    if !report.findings.is_empty() {
      out.write_string("\n### 规则检查\n\n")
      out.write_string("| 规则 | 结果 | 实际值 | 限制 |\n")
      out.write_string("| --- | --- | --- | --- |\n")
      for finding in report.findings {
        out.write_string(
          "| " +
          markdown_cell(finding.rule) +
          " | " +
          markdown_cell(finding.message) +
          " | " +
          markdown_cell(finding.actual.stringify()) +
          " | " +
          markdown_cell(finding.limit.stringify()) +
          " |\n",
        )
      }
    }
    write_abi_summary(out, report.abi)
    write_section_changes(out, release_baseline_facts(report), report.after)
  }
  out.to_string()
}

///|
fn release_baseline_facts(report : ReleaseArtifactReport) -> @release.Facts? {
  match report.baseline {
    Some(facts) => Some(facts)
    None => report.before
  }
}

///|
fn status_label(status : String) -> String {
  match status {
    "passed" => "通过"
    "failed" => "未通过"
    _ => "错误"
  }
}

///|
fn markdown_optional_bytes(facts : @release.Facts?) -> String {
  match facts {
    Some(facts) => facts.bytes.to_string()
    None => "—"
  }
}

///|
fn markdown_delta(before : @release.Facts?, after : @release.Facts?) -> String {
  match (before, after) {
    (Some(before), Some(after)) =>
      signed_bytes(after.bytes.to_int64() - before.bytes.to_int64())
    _ => "—"
  }
}

///|
fn signed_bytes(value : Int64) -> String {
  if value > 0L {
    "+" + value.to_string() + " B"
  } else {
    value.to_string() + " B"
  }
}

///|
fn write_abi_summary(out : StringBuilder, abi : ReleaseAbiResult?) -> Unit {
  match abi {
    None => ()
    Some(abi) => {
      out.write_string("\n### MoonHostABI\n\n")
      let outcome = json_object_string(abi.report, "outcome").unwrap_or(
        "未知",
      )
      let compatibility = json_nested_string(
        abi.report,
        "compatibility",
        "classification",
      ).unwrap_or("未评估")
      let baseline_status = json_nested_string(abi.report, "baseline", "status").unwrap_or(
        "未知",
      )
      let generator_status = json_nested_string(
        abi.report,
        "generator",
        "status",
      ).unwrap_or("未知")
      let bridge_status = if abi.passed { "通过" } else { "未通过" }
      out.write_string(
        "| 原始结果 | 桥接判定 | ABI 兼容性 | 基线 | 生成器 | 退出码 |\n",
      )
      out.write_string("| --- | --- | --- | --- | --- | ---: |\n")
      out.write_string(
        "| " +
        markdown_cell(outcome) +
        " | " +
        bridge_status +
        " | " +
        markdown_cell(compatibility) +
        " | " +
        markdown_cell(baseline_status) +
        " | " +
        markdown_cell(generator_status) +
        " | " +
        abi.exit_code.to_string() +
        " |\n",
      )
      match abi.error {
        Some(error) =>
          out.write_string("\n验证器信息：" + markdown_cell(error) + "\n")
        None => ()
      }
      match json_nested_string(abi.report, "artifact", "sha256") {
        Some(hash) =>
          out.write_string("\n产物 SHA-256：" + markdown_cell(hash) + "\n")
        None => ()
      }
    }
  }
}

///|
fn json_object_string(value : Json?, key : String) -> String? {
  match value {
    Some(Json::Object(object)) =>
      match object.get(key) {
        Some(Json::String(text)) => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
fn json_nested_string(value : Json?, outer : String, inner : String) -> String? {
  match value {
    Some(Json::Object(object)) =>
      match object.get(outer) {
        Some(Json::Object(nested)) =>
          match nested.get(inner) {
            Some(Json::String(text)) => Some(text)
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn write_section_changes(
  out : StringBuilder,
  before : @release.Facts?,
  after : @release.Facts?,
) -> Unit {
  match (before, after) {
    (Some(before), Some(after)) => {
      let before_totals = section_totals(before.sections)
      let after_totals = section_totals(after.sections)
      let names : Array[String] = []
      for name in before_totals.keys() {
        names.push(name)
      }
      for name in after_totals.keys() {
        if !names.contains(name) {
          names.push(name)
        }
      }
      let changed : Array[(String, Int64, Int64)] = []
      for name in names {
        let old_size = before_totals.get(name).unwrap_or(0L)
        let new_size = after_totals.get(name).unwrap_or(0L)
        if old_size != new_size {
          changed.push((name, old_size, new_size))
        }
      }
      changed.sort_by(fn(left, right) {
        let left_growth = left.2 - left.1
        let right_growth = right.2 - right.1
        if left_growth > right_growth {
          -1
        } else if left_growth < right_growth {
          1
        } else {
          left.0.lexical_compare(right.0)
        }
      })
      if !changed.is_empty() {
        out.write_string("\n### Section 变化\n\n")
        out.write_string(
          "比较来源：已配置基线时使用基线，否则使用输入产物。\n\n",
        )
        out.write_string("| Section | 比较字节 | 最终字节 | 变化 |\n")
        out.write_string("| --- | ---: | ---: | ---: |\n")
        for (name, old_size, new_size) in changed {
          out.write_string(
            "| " +
            markdown_cell(name) +
            " | " +
            old_size.to_string() +
            " | " +
            new_size.to_string() +
            " | " +
            signed_bytes(new_size - old_size) +
            " |\n",
          )
        }
      }
    }
    _ => ()
  }
}

///|
fn section_totals(
  sections : Array[@release.SectionMetric],
) -> Map[String, Int64] {
  let totals : Map[String, Int64] = Map([])
  for section in sections {
    let current = totals.get(section.name).unwrap_or(0L)
    totals.set(section.name, current + section.bytes.to_int64())
  }
  totals
}

///|
fn markdown_cell(value : String) -> String {
  let out = StringBuilder()
  let mut after_cr = false
  for char in value {
    if after_cr && char == '\n' {
      after_cr = false
      continue
    }
    after_cr = false
    match char {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' => out.write_string("&quot;")
      '\'' => out.write_string("&#39;")
      '|' => out.write_string("&#124;")
      '`' => out.write_string("&#96;")
      '\\' => out.write_string("&#92;")
      '\n' => out.write_string("<br>")
      '\r' => {
        out.write_string("<br>")
        after_cr = true
      }
      _ => out.write_char(char)
    }
  }
  out.to_string()
}
