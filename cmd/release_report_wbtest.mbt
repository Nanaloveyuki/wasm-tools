///|
fn report_facts(
  bytes : Int32,
  sections : Array[(String, Int32)],
) -> @release.Facts {
  {
    bytes,
    sha256: "hash-" + bytes.to_string(),
    sections: sections.map(fn(item) { { name: item.0, bytes: item.1, } }),
    imports: [],
    custom_sections: [],
  }
}

///|
fn report_abi_json(text : String) -> Json? {
  Some(@json.parse(text) catch { _ => return None })
}

///|
test "markdown summarizes a mixed batch and aggregates section changes" {
  let compatible_abi = report_abi_json(
    (
      #|{"outcome":"compatible","artifact":{"sha256":"abc123"},"baseline":{"status":"valid"},"compatibility":{"classification":"compatible"},"generator":{"status":"representable"}}
    ),
  ).unwrap_or(Json::null())
  let reports : Array[ReleaseArtifactReport] = [
    {
      id: "app",
      input: "dist/app|preview.wasm",
      baseline_path: Some("release/app.wasm"),
      before: Some(report_facts(105, [("code", 61)])),
      after: Some(
        report_facts(120, [
          ("code", 20),
          ("code", 38),
          ("data", 15),
          ("import", 15),
          ("type", 15),
        ]),
      ),
      baseline: Some(
        report_facts(100, [
          ("code", 48),
          ("data", 0),
          ("import", 0),
          ("type", 0),
        ]),
      ),
      findings: [],
      abi: Some({
        passed: true,
        exit_code: 0,
        report: Some(compatible_abi),
        error: None,
      }),
      error: None,
      exit_code: 0,
    },
    {
      id: "broken",
      input: "src/bad\n<tag>.wasm",
      baseline_path: None,
      before: Some(report_facts(4, [])),
      after: Some(report_facts(8, [])),
      baseline: None,
      findings: [
        {
          rule: "max|bytes",
          message: "too big\n<tag> `x` &",
          actual: Json::string("value|with `pipe`"),
          limit: Json::number(4.0),
        },
      ],
      abi: Some({
        passed: false,
        exit_code: 0,
        report: Some(compatible_abi),
        error: Some("report hash did not match the inspected artifact"),
      }),
      error: Some("invalid <wasm>\nmodule"),
      exit_code: 1,
    },
  ]
  let markdown = release_markdown("check", reports, None)
  inspect(markdown.contains("总体状态：未通过"), content="true")
  inspect(
    markdown.contains(
      "| app | dist/app&#124;preview.wasm | 105 | 120 | 100 | +20 B | 通过 |",
    ),
    content="true",
  )
  inspect(
    markdown.contains(
      "| broken | src/bad<br>&lt;tag&gt;.wasm | 4 | 8 | — | +4 B | 未通过 |",
    ),
    content="true",
  )
  inspect(
    markdown.contains(
      "变化按基线计算；未配置基线时按输入产物计算。",
    ),
    content="true",
  )
  inspect(markdown.contains("| data | 0 | 15 | +15 B |"), content="true")
  inspect(markdown.contains("| import | 0 | 15 | +15 B |"), content="true")
  inspect(markdown.contains("| type | 0 | 15 | +15 B |"), content="true")
  inspect(markdown.contains("| code | 48 | 58 | +10 B |"), content="true")
  inspect(
    markdown.contains(
      "| data | 0 | 15 | +15 B |\n| import | 0 | 15 | +15 B |\n| type | 0 | 15 | +15 B |\n| code | 48 | 58 | +10 B |",
    ),
    content="true",
  )
  inspect(
    markdown.contains(
      "比较来源：已配置基线时使用基线，否则使用输入产物。",
    ),
    content="true",
  )
  inspect(
    markdown.contains(
      "| compatible | 未通过 | compatible | valid | representable | 0 |",
    ),
    content="true",
  )
  inspect(
    markdown.contains("report hash did not match the inspected artifact"),
    content="true",
  )
  inspect(
    markdown.contains(
      "| max&#124;bytes | too big<br>&lt;tag&gt; &#96;x&#96; &amp; | &quot;value&#124;with &#96;pipe&#96;&quot; | 4 |",
    ),
    content="true",
  )
  inspect(
    markdown.contains("错误：invalid &lt;wasm&gt;<br>module"),
    content="true",
  )
}

///|
test "markdown reports process delta from before when no baseline exists" {
  let report : ReleaseArtifactReport = {
    id: "prepared",
    input: "module.wasm",
    baseline_path: None,
    before: Some(report_facts(100, [("code", 20)])),
    after: Some(report_facts(90, [("code", 10)])),
    baseline: None,
    findings: [],
    abi: None,
    error: None,
    exit_code: 0,
  }
  let markdown = release_markdown("prepare", [report], Some("dist/out"))
  inspect(markdown.contains("输出目录：dist/out"), content="true")
  inspect(
    markdown.contains(
      "| prepared | module.wasm | 100 | 90 | — | -10 B | 通过 |",
    ),
    content="true",
  )
  inspect(
    markdown.contains("| Section | 比较字节 | 最终字节 | 变化 |"),
    content="true",
  )
  inspect(markdown.contains("| code | 20 | 10 | -10 B |"), content="true")
}
