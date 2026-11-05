///|
pub fn help_text() -> String {
  let text =
    #|wsm - WebAssembly binary toolkit
    #|
    #|Usage: wsm <COMMAND> [OPTIONS] [FILE]
    #|
    #|Commands:
    #|  validate [FILE]        Parse and validate a module or component
    #|  print [FILE]           Convert binary to WAT (-o FILE to write)
    #|  parse [FILE]           Convert WAT to binary (-o FILE to write)
    #|  dump [FILE]            List sections (--instructions for offsets)
    #|  strip [FILE]           Remove custom sections (--keep NAME to retain)
    #|  metadata [FILE]        Show name and producers sections
#|  size [FILE]            Report section and function sizes
    #|  component wit [FILE]   Extract the WIT package from a component
    #|  help                   Show this message
    #|
    #|Common options:
    #|  -o, --output FILE      Write to FILE instead of stdout
    #|      --json             Structured output (dump, metadata)
    #|  -h, --help             Show this message
    #|  -V, --version          Show version
    #|
    #|Input defaults to stdin; `-` also means stdin.
    #|WIT/WAC language tools live in `moonx moonrockz/wasm-devkit`.
  text
}
