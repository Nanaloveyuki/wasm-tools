///|
pub fn help_text() -> String {
  let text =
    #|wsm - WebAssembly contract and binary tools
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
    #|  opt [FILE]             Optimize with moon-wasm-opt (-Oz, --passes)
    #|  symbolize [FILE] ADDR  Map a wasm stack address to a function name
    #|  component wit [FILE]   Extract the WIT package from a component
    #|  contract snapshot      Write a Core ABI snapshot as JSON
    #|  contract check         Compare a module with a Core ABI snapshot
    #|  contract wit           Snapshot/check a selected WIT world
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
