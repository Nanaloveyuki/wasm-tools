///|
fn bundle_manifest(text : String) -> Manifest raise {
  parse_manifest(text) catch {
    error => fail(error.message())
  }
}

///|
test "manifest parses files, compression relations, and consumer defaults" {
  let manifest = bundle_manifest(
    (
      #|{"format_version":1,"files":[
      #| {"path":"app.mjs"},
      #| {"path":"app.wasm","kind":"wasm"},
      #| {"path":"app.wasm.gz","encoding":"gzip","source":"app.wasm"},
      #| {"path":"worker.mjs"}
      #|],"consumers":[{"name":"smoke-1","entry":"app.mjs","requires":["app.wasm","worker.mjs"],"export":"run","args":[],"expected":null}]}
    ),
  )
  inspect(manifest.format_version, content="1")
  inspect(manifest.root, content=".")
  inspect(manifest.files.length(), content="4")
  inspect(manifest.files[2].encoding is Encoding::Gzip, content="true")
  assert_eq(manifest.files[2].source, Some("app.wasm"))
  inspect(manifest.consumers[0].timeout_ms, content="5000")
  assert_eq(manifest.consumers[0].expected.stringify(), "null")
}

///|
test "manifest rejects malformed JSON shape, unknown keys, and duplicate keys" {
  assert_manifest_error(
    "{\"format_version\":1,\"files\":[{\"path\":\"a\"}],\"extra\":true}", "unknown key",
  )
  assert_manifest_error(
    "{\"format_version\":1,\"format_version\":1,\"files\":[{\"path\":\"a\"}]}", "invalid JSON",
  )
  assert_manifest_error(
    "{\"format_version\":1.5,\"files\":[{\"path\":\"a\"}]}", "integer",
  )
}

///|
test "manifest rejects unsafe paths and case-insensitive prefix conflicts" {
  for
    path in [
      "/rooted", "../escape", "dir/./file", "dir//file", "C:/app.js", "folder\\file",
      "CON.txt", "a/b.", "a?b",
    ] {
    let json = "{\"format_version\":1,\"files\":[{\"path\":\"" + path + "\"}]}"
    assert_manifest_error(json, "path")
  }
  assert_manifest_error(
    "{\"format_version\":1,\"files\":[{\"path\":\"App.js\"},{\"path\":\"app.JS\"}]}",
    "duplicate path",
  )
  assert_manifest_error(
    "{\"format_version\":1,\"files\":[{\"path\":\"assets\"},{\"path\":\"assets/icon.png\"}]}",
    "prefix conflict",
  )
}

///|
test "manifest enforces compression source and wasm identity rules" {
  assert_manifest_error(
    "{\"format_version\":1,\"files\":[{\"path\":\"app.gz\",\"encoding\":\"gzip\"}]}",
    "source is required",
  )
  assert_manifest_error(
    "{\"format_version\":1,\"files\":[{\"path\":\"app.gz\",\"encoding\":\"gzip\",\"source\":\"missing\"}]}",
    "source is undeclared",
  )
  assert_manifest_error(
    "{\"format_version\":1,\"files\":[{\"path\":\"app.gz\",\"encoding\":\"gzip\",\"source\":\"app.br\"},{\"path\":\"app.br\",\"encoding\":\"br\",\"source\":\"app.wasm\"},{\"path\":\"app.wasm\",\"kind\":\"wasm\"}]}",
    "source must use identity",
  )
  assert_manifest_error(
    "{\"format_version\":1,\"files\":[{\"path\":\"app.wasm.gz\",\"kind\":\"wasm\",\"encoding\":\"gzip\",\"source\":\"app.wasm\"},{\"path\":\"app.wasm\",\"kind\":\"wasm\"}]}",
    "requires identity",
  )
}

///|
test "consumer contract requires declared mjs identity entry and known requirements" {
  assert_manifest_error(
    "{\"format_version\":1,\"files\":[{\"path\":\"app.js\"}],\"consumers\":[{\"name\":\"smoke\",\"entry\":\"app.js\",\"export\":\"run\",\"expected\":true}]}",
    "end in .mjs",
  )
  assert_manifest_error(
    "{\"format_version\":1,\"files\":[{\"path\":\"app.mjs.gz\",\"encoding\":\"gzip\",\"source\":\"app.mjs\"},{\"path\":\"app.mjs\"}],\"consumers\":[{\"name\":\"smoke\",\"entry\":\"app.mjs.gz\",\"export\":\"run\",\"expected\":true}]}",
    "end in .mjs",
  )
  assert_manifest_error(
    "{\"format_version\":1,\"files\":[{\"path\":\"app.mjs\"}],\"consumers\":[{\"name\":\"smoke\",\"entry\":\"app.mjs\",\"requires\":[\"missing.wasm\"],\"export\":\"run\",\"expected\":true}]}",
    "undeclared file",
  )
  assert_manifest_error(
    "{\"format_version\":1,\"files\":[{\"path\":\"app.mjs\"}],\"consumers\":[{\"name\":\"smoke\",\"entry\":\"app.mjs\",\"export\":\"run\",\"expected\":true,\"timeout_ms\":99}]}",
    "between 100 and 60000",
  )
}

///|
test "manifest enforces item limits and unique portable consumer names" {
  assert_manifest_error(
    "{\"format_version\":1,\"files\":[{\"path\":\"app.mjs\"}],\"consumers\":[{\"name\":\"X\",\"entry\":\"app.mjs\",\"export\":\"run\",\"expected\":null},{\"name\":\"x\",\"entry\":\"app.mjs\",\"export\":\"run\",\"expected\":null}]}",
    "duplicate name",
  )
  assert_manifest_error(
    "{\"format_version\":1,\"files\":[{\"path\":\"app.mjs\"}],\"consumers\":[{\"name\":\"bad name\",\"entry\":\"app.mjs\",\"export\":\"run\",\"expected\":null}]}",
    "ASCII letters",
  )
}

///|
fn assert_manifest_error(text : String, expected : String) -> Unit raise {
  let parsed = parse_manifest(text) catch {
    error => {
      if !error.message().contains(expected) {
        fail(
          "expected error containing `" +
          expected +
          "`, got: " +
          error.message(),
        )
      }
      return
    }
  }
  ignore(parsed)
  fail("expected manifest error containing `" + expected + "`")
}
