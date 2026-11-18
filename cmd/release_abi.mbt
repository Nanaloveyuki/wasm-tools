///|
priv struct ReleaseAbiResult {
  passed : Bool
  exit_code : Int32
  report : Json?
  error : String?
}

///|
async fn release_verify_abi(
  data : Bytes,
  baseline : String,
  executable : String,
) -> ReleaseAbiResult noraise {
  let dir = @fs.tmpdir(prefix="wsm-release-abi-") catch {
    e =>
      return {
        passed: false,
        exit_code: 1,
        report: None,
        error: Some("cannot create temporary directory: " + e.to_string()),
      }
  }
  let candidate = dir + "/candidate.wasm"
  defer {
    let _ = @fs.remove(candidate) catch { _ => () }
    let _ = @fs.rmdir(dir) catch { _ => () }
  }
  @fs.write_file(candidate, data) catch {
    e =>
      return {
        passed: false,
        exit_code: 1,
        report: None,
        error: Some("cannot write temporary candidate: " + e.to_string()),
      }
  }
  let (exit_code, stdout, stderr) = @process.collect_output(executable, [
    "verify", candidate, "--against", baseline, "--format", "json",
  ]) catch {
    e =>
      return {
        passed: false,
        exit_code: 1,
        report: None,
        error: Some("cannot run " + executable + ": " + e.to_string()),
      }
  }
  let output = stdout.text() catch {
    _ =>
      return {
        passed: false,
        exit_code,
        report: None,
        error: Some("moonhostabi returned non-UTF-8 JSON output"),
      }
  }
  let stderr_text = stderr.text() catch { _ => "" }
  let report = @json.parse(output, reject_duplicate_keys=true) catch {
    _ =>
      return {
        passed: false,
        exit_code,
        report: None,
        error: Some(
          release_abi_add_stderr(
            "moonhostabi returned malformed JSON", stderr_text,
          ),
        ),
      }
  }
  let validation = validate_release_abi_report(
    report,
    @crypto.bytes_to_hex_string(@crypto.sha256(data)),
    exit_code,
  )
  let passed = exit_code == 0 &&
    validation == None &&
    release_abi_report_is_compatible(report)
  let error = if passed {
    None
  } else {
    let message = match validation {
      Some(reason) => reason
      None if exit_code != 0 =>
        "moonhostabi exited with code " + exit_code.to_string()
      None => "moonhostabi verification did not pass"
    }
    Some(release_abi_add_stderr(message, stderr_text))
  }
  { passed, exit_code, report: Some(report), error, }
}

///|
fn release_abi_add_stderr(message : String, stderr : String) -> String {
  if stderr.trim().is_empty() {
    message
  } else {
    message + ": " + stderr.trim().to_owned()
  }
}

///|
fn release_abi_report_is_compatible(report : Json) -> Bool {
  match report {
    Object(root) =>
      match
        (
          root.get("outcome"),
          root.get("artifact"),
          root.get("baseline"),
          root.get("compatibility"),
          root.get("resources"),
          root.get("contract"),
          root.get("generator"),
        ) {
        (
          Some(String("compatible")),
          Some(Object(artifact)),
          Some(Object(baseline)),
          Some(Object(compatibility)),
          resources,
          Some(Object(contract)),
          Some(Object(generator)),
        ) => {
          let base_ok = match baseline.get("status") {
            Some(String("valid")) => true
            _ => false
          }
          let contract_ok = match contract.get("status") {
            Some(String("valid" | "notProvided")) => true
            _ => false
          }
          let resources_ok = match resources {
            None => true
            Some(Object(value)) =>
              match (value.get("status"), value.get("classification")) {
                (Some(String("evaluated")), Some(String("compatible"))) => true
                _ => false
              }
            _ => false
          }
          let verification_ok = match
            (
              artifact.get("status"),
              compatibility.get("status"),
              compatibility.get("classification"),
              generator.get("status"),
            ) {
            (
              Some(String("valid")),
              Some(String("evaluated")),
              Some(String("compatible")),
              Some(String("representable")),
            ) => true
            _ => false
          }
          base_ok && contract_ok && resources_ok && verification_ok
        }
        _ => false
      }
    _ => false
  }
}

///|
fn validate_release_abi_report(
  report : Json,
  expected_sha256 : String,
  exit_code : Int32,
) -> String? {
  match report {
    Object(root) => {
      let schema = match root.get("schemaVersion") {
        Some(Number(value, ..)) => {
          let integer = value.to_int()
          if integer.to_double() == value && (integer == 1 || integer == 2) {
            Some(integer)
          } else {
            None
          }
        }
        _ => None
      }
      if schema == None {
        return Some("unsupported or malformed report schemaVersion")
      }
      let outcome = match root.get("outcome") {
        Some(String(value)) => value
        _ => return Some("missing or unknown verification outcome")
      }
      if outcome != "compatible" &&
        outcome != "breaking" &&
        outcome != "unknown" &&
        outcome != "invalid" &&
        outcome != "adapterMismatch" {
        return Some("missing or unknown verification outcome")
      }
      let expected_exit_code = match outcome {
        "compatible" => 0
        "breaking" => 2
        "unknown" | "invalid" => 3
        "adapterMismatch" => 4
        _ => 1
      }
      if exit_code != expected_exit_code {
        return Some("verification outcome does not match process exit code")
      }
      let artifact = match root.get("artifact") {
        Some(Object(value)) => value
        _ => return Some("missing or malformed artifact report")
      }
      let artifact_status = match artifact.get("status") {
        Some(String(value)) => value
        _ => return Some("missing or unknown artifact status")
      }
      if artifact_status != "valid" &&
        artifact_status != "unsupported" &&
        artifact_status != "invalid" {
        return Some("missing or unknown artifact status")
      }
      match artifact.get("sha256") {
        Some(String(value)) =>
          if value != expected_sha256 {
            return Some("artifact SHA-256 does not match candidate")
          }
        _ => return Some("missing or malformed artifact SHA-256")
      }
      let baseline = match root.get("baseline") {
        Some(Object(value)) => value
        _ => return Some("missing or malformed baseline report")
      }
      let baseline_valid = match baseline.get("status") {
        Some(String("valid" | "invalid")) => true
        _ => false
      }
      if !baseline_valid {
        return Some("malformed baseline report")
      }
      let provenance = match root.get("provenance") {
        Some(Object(value)) => value
        _ => return Some("missing or malformed provenance report")
      }
      if !release_abi_optional_bool(provenance.get("artifactMatchesBaseline")) ||
        !release_abi_optional_bool(provenance.get("abiMatchesBaseline")) {
        return Some("malformed provenance report")
      }
      match root.get("compatibility") {
        Some(Object(value)) => {
          let valid = match (value.get("status"), value.get("classification")) {
            (Some(String("evaluated")), Some(String(classification))) =>
              classification == "compatible" ||
              classification == "breaking" ||
              classification == "unknown"
            (Some(String("notEvaluated")), Some(Null)) => true
            _ => false
          }
          if !valid {
            return Some("malformed compatibility report")
          }
        }
        _ => return Some("malformed compatibility report")
      }
      match root.get("generator") {
        Some(Object(value)) => {
          let valid = match value.get("status") {
            Some(String("representable" | "unrepresentable" | "notEvaluated")) =>
              true
            _ => false
          }
          if !valid {
            return Some("malformed generator report")
          }
        }
        _ => return Some("malformed generator report")
      }
      let contract = match root.get("contract") {
        Some(Object(value)) => value
        _ => return Some("missing or malformed contract report")
      }
      let contract_valid = match contract.get("status") {
        Some(String("notProvided" | "valid" | "invalid" | "notEvaluated")) =>
          true
        _ => false
      }
      if !contract_valid {
        return Some("malformed contract report")
      }
      if schema == Some(2) {
        match root.get("resources") {
          Some(Object(value)) => {
            let valid = match
              (value.get("status"), value.get("classification")) {
              (Some(String("evaluated")), Some(String(classification))) =>
                classification == "compatible" ||
                classification == "breaking" ||
                classification == "unknown"
              (Some(String("notEvaluated")), Some(Null)) => true
              _ => false
            }
            if !valid {
              return Some("malformed resource compatibility report")
            }
          }
          _ => return Some("schemaVersion 2 report is missing resources")
        }
      }
      None
    }
    _ => Some("verification report must be a JSON object")
  }
}

///|
fn release_abi_optional_bool(value : Json?) -> Bool {
  match value {
    Some(True | False | Null) => true
    _ => false
  }
}
