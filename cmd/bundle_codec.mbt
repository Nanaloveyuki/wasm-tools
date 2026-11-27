///|
async fn bundle_decode(
  encoded : Bytes,
  encoding : @bundle.Encoding,
  max_bytes : Int32,
  node : String,
) -> Bytes raise @cli.CliError {
  let encoding_name = match encoding {
    @bundle.Encoding::Identity =>
      raise @cli.CliError::Invalid("identity encoding does not need decoding")
    @bundle.Encoding::Gzip => "gzip"
    @bundle.Encoding::Brotli => "br"
  }
  if max_bytes < 0 || max_bytes >= 2147483647 {
    raise @cli.CliError::Invalid("decoded byte limit is out of range")
  }
  let dir = @fs.tmpdir(prefix="wsm-bundle-codec-") catch {
    error =>
      raise @cli.CliError::Io(
        "cannot create temporary codec directory: " + error.to_string(),
      )
  }
  let input_path = dir + "/encoded.bin"
  defer {
    let _ = @fs.remove(input_path) catch { _ => () }
    let _ = @fs.remove(dir) catch { _ => () }
  }
  @fs.write_binary(input_path, encoded) catch {
    error =>
      raise @cli.CliError::Io(
        "cannot write temporary codec input: " + error.to_string(),
      )
  }
  let args = [
    "-e",
    bundle_codec_script(),
    "--",
    encoding_name,
    input_path,
    (max_bytes + 1).to_string(),
  ]
  let result = @process.run(
    node,
    args,
    extra_env=bundle_node_environment(),
    inherit_env=false,
    stdout=Collect,
    stderr=Collect,
    cwd=dir,
  ) catch {
    error =>
      raise @cli.CliError::Io(
        "cannot run Node.js codec helper: " + error.to_string(),
      )
  }
  if result.exit_code == 2 {
    raise @cli.CliError::Io(
      "Node.js 20 or newer is required for gzip and Brotli decoding",
    )
  }
  if result.exit_code != 0 {
    let detail = result.stderr_text() catch { _ => "" }
    let detail = detail.trim().to_owned()
    let suffix = if detail.is_empty() { "" } else { ": " + detail }
    raise @cli.CliError::Invalid(encoding_name + " decoding failed" + suffix)
  }
  result.stdout_binary()
}

///|
fn bundle_node_environment() -> Map[String, String] {
  let parent = @env.get_env_vars()
  let environment : Map[String, String] = Map([])
  for key in ["PATH", "Path", "SystemRoot", "WINDIR", "TMP", "TEMP", "TMPDIR"] {
    match parent.get(key) {
      Some(value) => environment.set(key, value)
      None => ()
    }
  }
  environment
}

///|
fn bundle_codec_script() -> String {
  let script =
    #|const fs = require("node:fs");
    #|const zlib = require("node:zlib");
    #|const [encoding, inputPath, limitText] = process.argv.slice(1);
    #|const version = Number.parseInt(process.versions.node.split(".")[0], 10);
    #|if (!Number.isInteger(version) || version < 20) {
    #|  process.stderr.write("Node.js 20 or newer is required\n");
    #|  process.exit(2);
    #|}
    #|try {
    #|  const limit = Number(limitText);
    #|  if (!Number.isSafeInteger(limit) || limit < 1) throw new Error("invalid output limit");
    #|  const input = fs.readFileSync(inputPath);
    #|  const decoder = encoding === "gzip" ? zlib.gunzipSync :
    #|    encoding === "br" ? zlib.brotliDecompressSync : null;
    #|  if (decoder === null) throw new Error("unsupported encoding");
    #|  const result = decoder(input, { info: true, maxOutputLength: limit });
    #|  if (result.engine.bytesWritten !== input.length) throw new Error("encoded input has trailing bytes");
    #|  process.stdout.write(result.buffer);
    #|} catch (error) {
    #|  const message = String(error && error.message || error).replace(/[\r\n\t]/g, " ").slice(0, 512);
    #|  process.stderr.write(message + "\n");
    #|  process.exit(1);
    #|}
  script
}
