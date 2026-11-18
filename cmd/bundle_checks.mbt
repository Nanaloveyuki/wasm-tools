///|
async fn bundle_check_compressions(
  manifest : @bundle.Manifest,
  data : Map[String, Bytes],
  findings : Array[@bundle.Finding],
  node : String,
) -> Array[Json] raise @cli.CliError {
  let reports : Array[Json] = []
  for file in manifest.files {
    if file.encoding is Identity {
      continue
    }
    let source = file.source.unwrap_or("")
    let encoding = match file.encoding {
      Gzip => "gzip"
      Brotli => "br"
      Identity => "identity"
    }
    let mut status = "skipped"
    let mut decoded_bytes : Int32? = None
    let mut decoded_sha256 : String? = None
    let mut error : String? = Some(
      "compressed file or original could not be captured",
    )
    if data.get(file.path) is Some(encoded) && data.get(source) is Some(raw) {
      let decoded = Some(
        bundle_decode(encoded, file.encoding, raw.length(), node),
      ) catch {
        @cli.CliError::Invalid(message) => {
          findings.push({
            code: "compression_invalid",
            path: file.path,
            related_path: Some(source),
            message,
          })
          status = "failed"
          error = Some(message)
          None
        }
        e => raise e
      }
      if decoded is Some(decoded) {
        decoded_bytes = Some(decoded.length())
        decoded_sha256 = Some(
          @crypto.bytes_to_hex_string(@crypto.sha256(decoded)),
        )
        if decoded == raw {
          status = "passed"
          error = None
        } else {
          let message = "decoded bytes differ from declared original"
          findings.push({
            code: "compression_mismatch",
            path: file.path,
            related_path: Some(source),
            message,
          })
          status = "failed"
          error = Some(message)
        }
      }
    }
    reports.push(
      Json::object({
        "path": Json::string(file.path),
        "source": Json::string(source),
        "encoding": Json::string(encoding),
        "status": Json::string(status),
        "decoded_bytes": match decoded_bytes {
          Some(n) => Json::number(n.to_double())
          None => Json::null()
        },
        "decoded_sha256": release_optional_string(decoded_sha256),
        "error": release_optional_string(error),
      }),
    )
  }
  reports
}
