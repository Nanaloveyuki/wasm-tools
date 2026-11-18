///|
priv struct BundleConsumerPacket {
  status : String
  actual_present : Bool
  actual : Json
  error : String?
  stdout : String
  stderr : String
  logs_truncated : Bool
}

///|
async fn bundle_check_consumers(
  manifest : @bundle.Manifest,
  data : Map[String, Bytes],
  findings : Array[@bundle.Finding],
  node : String,
) -> Array[Json] raise @cli.CliError {
  let reports : Array[Json] = []
  for consumer in manifest.consumers {
    reports.push(
      bundle_check_one_consumer(manifest, consumer, data, findings, node),
    )
  }
  reports
}

///|
async fn bundle_check_one_consumer(
  manifest : @bundle.Manifest,
  consumer : @bundle.Consumer,
  data : Map[String, Bytes],
  findings : Array[@bundle.Finding],
  node : String,
) -> Json raise @cli.CliError {
  let files = manifest.files.map(file => file.path)
  for path in files {
    if data.get(path) is None {
      return bundle_consumer_row(
        consumer,
        "skipped",
        None,
        None,
        Some("captured file is unavailable: " + path),
        "",
        "",
        false,
      )
    }
  }

  let directory = @fs.tmpdir(prefix="wsm-bundle-consumer-") catch {
    error =>
      raise @cli.CliError::Io(
        "cannot create consumer snapshot: " + error.to_string(),
      )
  }
  let snapshot = release_path(directory, "package")
  let launcher = release_path(directory, "launcher.cjs")
  let runner = release_path(directory, "consumer.cjs")
  let config_path = release_path(directory, "consumer-config.json")
  let result_path = release_path(directory, "consumer-result.json")
  defer {
    let _ = @fs.rmdir(directory, recursive=true) catch { _ => () }
  }
  @fs.mkdir(snapshot) catch {
    error =>
      raise @cli.CliError::Io(
        "cannot create consumer snapshot directory: " + error.to_string(),
      )
  }
  for path in files {
    let bytes = data.get(path).unwrap_or(b"")
    let destination = release_path(snapshot, path)
    let parent = @path.Path(destination).dirname().to_string()
    @fs.mkdir(parent, recursive=true, allow_exist=true) catch {
      error =>
        raise @cli.CliError::Io(
          "cannot create consumer snapshot path: " + error.to_string(),
        )
    }
    @fs.write_file(destination, bytes) catch {
      error =>
        raise @cli.CliError::Io(
          "cannot write consumer snapshot file: " + error.to_string(),
        )
    }
  }
  @fs.write_file(launcher, @utf8.encode(bundle_consumer_launcher_script())) catch {
    error =>
      raise @cli.CliError::Io(
        "cannot write consumer launcher: " + error.to_string(),
      )
  }
  @fs.write_file(runner, @utf8.encode(bundle_consumer_runner_script())) catch {
    error =>
      raise @cli.CliError::Io(
        "cannot write consumer runner: " + error.to_string(),
      )
  }
  let config = Json::object({
    "entry": Json::string(release_path(snapshot, consumer.entry)),
    "export": Json::string(consumer.export_name),
    "args": Json::array(consumer.args),
    "result_path": Json::string(result_path),
    "snapshot_root": Json::string(snapshot),
    "timeout_ms": Json::number(consumer.timeout_ms.to_double()),
  })
  @fs.write_file(config_path, @utf8.encode(config.stringify())) catch {
    error =>
      raise @cli.CliError::Io(
        "cannot write consumer configuration: " + error.to_string(),
      )
  }
  let args = [launcher, runner, config_path]
  let (exit_code, stdout, stderr) = @process.collect_output(
    node,
    args,
    extra_env=bundle_node_environment(),
    inherit_env=false,
    cwd=snapshot,
  ) catch {
    error =>
      raise @cli.CliError::Io(
        "cannot run Node.js consumer harness: " + error.to_string(),
      )
  }
  if exit_code == 2 {
    raise @cli.CliError::Io(
      "Node.js 20 or newer is required for consumer checks",
    )
  }
  if exit_code != 0 {
    let detail = stderr.text() catch { _ => "" }
    raise @cli.CliError::Io(
      "Node.js consumer harness failed" + bundle_consumer_error_suffix(detail),
    )
  }
  let output = stdout.text() catch {
    _ =>
      raise @cli.CliError::Io(
        "Node.js consumer harness returned non-UTF-8 output",
      )
  }
  let packet_json = @json.parse(output, reject_duplicate_keys=true) catch {
    error =>
      raise @cli.CliError::Io(
        "Node.js consumer harness returned invalid JSON: " + error.to_string(),
      )
  }
  let packet = bundle_parse_consumer_packet(packet_json)
  match packet.status {
    "timeout" => {
      let message = packet.error.unwrap_or("consumer timed out")
      findings.push({
        code: "consumer_timeout",
        path: consumer.entry,
        related_path: None,
        message,
      })
      bundle_consumer_row(
        consumer,
        "failed",
        Some(packet.actual),
        Some(packet.actual_present),
        Some(message),
        packet.stdout,
        packet.stderr,
        packet.logs_truncated,
      )
    }
    "error" => {
      let message = packet.error.unwrap_or("consumer execution failed")
      findings.push({
        code: "consumer_runtime",
        path: consumer.entry,
        related_path: None,
        message,
      })
      bundle_consumer_row(
        consumer,
        "failed",
        Some(packet.actual),
        Some(packet.actual_present),
        Some(message),
        packet.stdout,
        packet.stderr,
        packet.logs_truncated,
      )
    }
    "completed" if packet.actual_present && packet.actual == consumer.expected =>
      bundle_consumer_row(
        consumer,
        "passed",
        Some(packet.actual),
        Some(true),
        None,
        packet.stdout,
        packet.stderr,
        packet.logs_truncated,
      )
    "completed" if packet.actual_present => {
      let message = "consumer result did not match expected JSON value"
      findings.push({
        code: "consumer_mismatch",
        path: consumer.entry,
        related_path: None,
        message,
      })
      bundle_consumer_row(
        consumer,
        "failed",
        Some(packet.actual),
        Some(true),
        Some(message),
        packet.stdout,
        packet.stderr,
        packet.logs_truncated,
      )
    }
    _ =>
      raise @cli.CliError::Io(
        "Node.js consumer harness returned an invalid status packet",
      )
  }
}

///|
fn bundle_consumer_row(
  consumer : @bundle.Consumer,
  status : String,
  actual : Json?,
  actual_present : Bool?,
  error : String?,
  stdout : String,
  stderr : String,
  logs_truncated : Bool,
) -> Json {
  Json::object({
    "name": Json::string(consumer.name),
    "entry": Json::string(consumer.entry),
    "status": Json::string(status),
    "expected": consumer.expected,
    "actual": actual.unwrap_or(Json::null()),
    "actual_present": Json::boolean(actual_present.unwrap_or(false)),
    "error": release_optional_string(error),
    "stdout": Json::string(stdout),
    "stderr": Json::string(stderr),
    "logs_truncated": Json::boolean(logs_truncated),
  })
}

///|
fn bundle_parse_consumer_packet(
  value : Json,
) -> BundleConsumerPacket raise @cli.CliError {
  let object = match value {
    Json::Object(object) => object
    _ =>
      raise @cli.CliError::Io(
        "Node.js consumer harness packet must be an object",
      )
  }
  for key in object.keys() {
    if ![
        "status", "actual_present", "actual", "error", "stdout", "stderr", "logs_truncated",
      ].contains(key) {
      raise @cli.CliError::Io(
        "Node.js consumer harness packet has unknown key: " + key,
      )
    }
  }
  let status = bundle_consumer_string(object, "status")
  let actual_present = bundle_consumer_bool(object, "actual_present")
  let actual = match object.get("actual") {
    Some(actual) => actual
    None =>
      raise @cli.CliError::Io(
        "Node.js consumer harness packet is missing actual",
      )
  }
  let error = match object.get("error") {
    Some(Json::Null) => None
    Some(Json::String(message)) => Some(message)
    _ =>
      raise @cli.CliError::Io(
        "Node.js consumer harness packet has invalid error",
      )
  }
  let stdout = bundle_consumer_string(object, "stdout")
  let stderr = bundle_consumer_string(object, "stderr")
  let logs_truncated = bundle_consumer_bool(object, "logs_truncated")
  if !["completed", "error", "timeout"].contains(status) {
    raise @cli.CliError::Io(
      "Node.js consumer harness packet has invalid status",
    )
  }
  if status == "completed" && !actual_present {
    raise @cli.CliError::Io(
      "Node.js consumer harness completed without an actual result",
    )
  }
  if status != "completed" && error is None {
    raise @cli.CliError::Io(
      "Node.js consumer harness failure packet is missing an error",
    )
  }
  { status, actual_present, actual, error, stdout, stderr, logs_truncated, }
}

///|
fn bundle_consumer_string(
  object : Map[String, Json],
  key : String,
) -> String raise @cli.CliError {
  match object.get(key) {
    Some(Json::String(value)) => value
    _ =>
      raise @cli.CliError::Io(
        "Node.js consumer harness packet has invalid " + key,
      )
  }
}

///|
fn bundle_consumer_bool(
  object : Map[String, Json],
  key : String,
) -> Bool raise @cli.CliError {
  match object.get(key) {
    Some(Json::True) => true
    Some(Json::False) => false
    _ =>
      raise @cli.CliError::Io(
        "Node.js consumer harness packet has invalid " + key,
      )
  }
}

///|
fn bundle_consumer_error_suffix(error : String) -> String {
  let message = error.trim().to_owned()
  if message.is_empty() {
    ""
  } else {
    ": " + message
  }
}

///|
fn bundle_consumer_launcher_script() -> String {
  let script =
    #|const fs = require("node:fs");
    #|const { spawnSync } = require("node:child_process");
    #|const [runner, configPath] = process.argv.slice(2);
    #|const version = Number.parseInt(process.versions.node.split(".")[0], 10);
    #|if (!Number.isInteger(version) || version < 20) {
    #|  process.stderr.write("Node.js 20 or newer is required");
    #|  process.exit(2);
    #|}
    #|function capture(value) {
    #|  const bytes = value || Buffer.alloc(0);
    #|  return { text: bytes.subarray(0, 4096).toString("utf8"), truncated: bytes.length > 4096 };
    #|}
    #|let packet = { status: "error", actual_present: false, actual: null, error: null, stdout: "", stderr: "", logs_truncated: false };
    #|try {
    #|  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    #|  const timeout = Number(config.timeout_ms);
    #|  const result = spawnSync(process.execPath, [runner, configPath], {
    #|    cwd: config.snapshot_root,
    #|    env: process.env,
    #|    shell: false,
    #|    timeout,
    #|    killSignal: "SIGKILL",
    #|    maxBuffer: 1024 * 1024,
    #|  });
    #|  const stdout = capture(result.stdout);
    #|  const stderr = capture(result.stderr);
    #|  packet.stdout = stdout.text;
    #|  packet.stderr = stderr.text;
    #|  packet.logs_truncated = stdout.truncated || stderr.truncated;
    #|  if (result.error && result.error.code === "ETIMEDOUT") {
    #|    packet.status = "timeout";
    #|    packet.error = "consumer timed out after " + timeout + " ms";
    #|  } else if (result.error) {
    #|    packet.error = String(result.error.message || result.error).slice(0, 512);
    #|  } else if (result.status !== 0) {
    #|    packet.error = "consumer process exited with code " + result.status + (result.signal ? " (" + result.signal + ")" : "");
    #|  } else if (!fs.existsSync(config.result_path)) {
    #|    packet.error = "consumer exited without a JSON result";
    #|  } else {
    #|    if (fs.statSync(config.result_path).size > 1024 * 1024) throw new Error("consumer JSON result exceeds 1 MiB");
    #|    packet.actual = JSON.parse(fs.readFileSync(config.result_path, "utf8"));
    #|    packet.actual_present = true;
    #|    packet.status = "completed";
    #|    packet.error = null;
    #|  }
    #|} catch (error) {
    #|  packet.error = String(error && error.message || error).slice(0, 512);
    #|}
    #|process.stdout.write(JSON.stringify(packet));
  script
}

///|
fn bundle_consumer_runner_script() -> String {
  let script =
    #|const fs = require("node:fs");
    #|const { pathToFileURL } = require("node:url");
    #|function assertJson(value, ancestors) {
    #|  if (value === null || typeof value === "string" || typeof value === "boolean") return;
    #|  if (typeof value === "number") {
    #|    if (!Number.isFinite(value)) throw new Error("consumer returned a non-finite number");
    #|    return;
    #|  }
    #|  if (typeof value !== "object") throw new Error("consumer returned a non-JSON value");
    #|  if (ancestors.has(value)) throw new Error("consumer returned a cyclic value");
    #|  ancestors.add(value);
    #|  if (Array.isArray(value)) {
    #|    const keys = Reflect.ownKeys(value);
    #|    if (keys.length !== value.length + 1) throw new Error("consumer returned an array with extra properties");
    #|    for (let i = 0; i < value.length; i++) {
    #|      if (!Object.prototype.hasOwnProperty.call(value, i)) throw new Error("consumer returned an array with a hole");
    #|      const descriptor = Object.getOwnPropertyDescriptor(value, String(i));
    #|      if (!descriptor || !descriptor.enumerable || !("value" in descriptor)) throw new Error("consumer returned a non-JSON array property");
    #|      assertJson(descriptor.value, ancestors);
    #|    }
    #|  } else {
    #|    const prototype = Object.getPrototypeOf(value);
    #|    if (prototype !== Object.prototype && prototype !== null) throw new Error("consumer returned a non-plain object");
    #|    for (const key of Reflect.ownKeys(value)) {
    #|      if (typeof key !== "string") throw new Error("consumer returned a symbol property");
    #|      const descriptor = Object.getOwnPropertyDescriptor(value, key);
    #|      if (!descriptor || !descriptor.enumerable || !("value" in descriptor)) throw new Error("consumer returned a non-JSON object property");
    #|      assertJson(descriptor.value, ancestors);
    #|    }
    #|  }
    #|  ancestors.delete(value);
    #|}
    #|async function main() {
    #|  const [configPath] = process.argv.slice(2);
    #|  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    #|  const args = config.args;
    #|  if (!Array.isArray(args)) throw new Error("consumer arguments must be a JSON array");
    #|  const loaded = await import(pathToFileURL(config.entry).href);
    #|  const fn = loaded[config.export];
    #|  if (typeof fn !== "function") throw new Error("named export is not a function: " + config.export);
    #|  const actual = await fn(...args);
    #|  assertJson(actual, new Set());
    #|  const json = JSON.stringify(actual);
    #|  if (typeof json !== "string") throw new Error("consumer returned no JSON value");
    #|  if (Buffer.byteLength(json, "utf8") > 1024 * 1024) throw new Error("consumer JSON result exceeds 1 MiB");
    #|  fs.writeFileSync(config.result_path, json, { flag: "wx" });
    #|}
    #|main().catch((error) => {
    #|  process.stderr.write(String(error && error.message || error).slice(0, 512));
    #|  process.exitCode = 1;
    #|});
  script
}
