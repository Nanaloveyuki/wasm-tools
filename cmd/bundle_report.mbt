///|
fn bundle_report_json(
  manifest : String,
  root : String,
  files : Array[@bundle.FileObservation],
  findings : Array[@bundle.Finding],
  compressions : Array[Json],
  consumers : Array[Json],
) -> Json {
  Json::object({
    "format_version": Json::number(1.0),
    "mode": Json::string("bundle-check"),
    "manifest": Json::string(manifest),
    "root": Json::string(root),
    "status": Json::string(
      if findings.is_empty() {
        "passed"
      } else {
        "failed"
      },
    ),
    "files": Json::array(
      files.map(file => {
        Json::object({
          "path": Json::string(file.path),
          "bytes": match file.bytes {
            Some(n) => Json::number(n.to_double())
            None => Json::null()
          },
          "sha256": release_optional_string(file.sha256),
          "error": release_optional_string(file.error),
        })
      }),
    ),
    "findings": Json::array(
      findings.map(finding => {
        Json::object({
          "code": Json::string(finding.code),
          "path": Json::string(finding.path),
          "related_path": release_optional_string(finding.related_path),
          "message": Json::string(finding.message),
        })
      }),
    ),
    "compressions": Json::array(compressions),
    "consumers": Json::array(consumers),
  })
}

///|
fn bundle_markdown(report : Json) -> String {
  let out = StringBuilder()
  out.write_string("# WASM Bundle Report\n\n")
  out.write_string(
    "Status: " +
    markdown_cell(json_object_string(Some(report), "status").unwrap_or("error")) +
    "\n\n",
  )
  out.write_string(
    "| File | Bytes | SHA-256 | Error |\n| --- | ---: | --- | --- |\n",
  )
  if report is Json::Object(object) {
    if object.get("files") is Some(Json::Array(files)) {
      for file in files {
        let bytes = if file is Json::Object(row) {
          row.get("bytes").unwrap_or(Json::null()).stringify()
        } else {
          "null"
        }
        out.write_string(
          "| " +
          markdown_cell(json_object_string(Some(file), "path").unwrap_or("")) +
          " | " +
          bytes +
          " | " +
          markdown_cell(json_object_string(Some(file), "sha256").unwrap_or("")) +
          " | " +
          markdown_cell(json_object_string(Some(file), "error").unwrap_or("")) +
          " |\n",
        )
      }
    }
    if object.get("findings") is Some(Json::Array(findings)) &&
      !findings.is_empty() {
      out.write_string("\n| Code | Path | Finding |\n| --- | --- | --- |\n")
      for finding in findings {
        out.write_string(
          "| " +
          markdown_cell(json_object_string(Some(finding), "code").unwrap_or("")) +
          " | " +
          markdown_cell(json_object_string(Some(finding), "path").unwrap_or("")) +
          " | " +
          markdown_cell(
            json_object_string(Some(finding), "message").unwrap_or(""),
          ) +
          " |\n",
        )
      }
    }
    if object.get("compressions") is Some(Json::Array(compressions)) &&
      !compressions.is_empty() {
      out.write_string(
        "\n| Compressed file | Original | Encoding | Status | Decoded SHA-256 |\n| --- | --- | --- | --- | --- |\n",
      )
      for row in compressions {
        out.write_string(
          "| " +
          markdown_cell(json_object_string(Some(row), "path").unwrap_or("")) +
          " | " +
          markdown_cell(json_object_string(Some(row), "source").unwrap_or("")) +
          " | " +
          markdown_cell(json_object_string(Some(row), "encoding").unwrap_or("")) +
          " | " +
          markdown_cell(json_object_string(Some(row), "status").unwrap_or("")) +
          " | " +
          markdown_cell(
            json_object_string(Some(row), "decoded_sha256").unwrap_or(""),
          ) +
          " |\n",
        )
      }
    }
  }
  bundle_consumer_markdown(out, report)
  out.to_string()
}

///|
fn bundle_consumer_markdown(out : StringBuilder, report : Json) -> Unit {
  if report is Json::Object(object) &&
    object.get("consumers") is Some(Json::Array(consumers)) &&
    !consumers.is_empty() {
    out.write_string(
      "\n| Consumer | Entry | Status | Expected | Actual | Error |\n| --- | --- | --- | --- | --- | --- |\n",
    )
    for row in consumers {
      let expected = if row is Json::Object(fields) {
        fields.get("expected").unwrap_or(Json::null()).stringify()
      } else {
        "null"
      }
      let actual = if row is Json::Object(fields) {
        fields.get("actual").unwrap_or(Json::null()).stringify()
      } else {
        "null"
      }
      out.write_string(
        "| " +
        markdown_cell(json_object_string(Some(row), "name").unwrap_or("")) +
        " | " +
        markdown_cell(json_object_string(Some(row), "entry").unwrap_or("")) +
        " | " +
        markdown_cell(json_object_string(Some(row), "status").unwrap_or("")) +
        " | " +
        markdown_cell(expected) +
        " | " +
        markdown_cell(actual) +
        " | " +
        markdown_cell(json_object_string(Some(row), "error").unwrap_or("")) +
        " |\n",
      )
    }
  }
}
