///|
fn pad_left(value : String, width : Int) -> String {
  let out = StringBuilder()
  let mut pad = width - value.length()
  while pad > 0 {
    out.write_char(' ')
    pad = pad - 1
  }
  out.write_string(value)
  out.to_string()
}

///|
fn pad_right(value : String, width : Int) -> String {
  let out = StringBuilder()
  out.write_string(value)
  let mut pad = width - value.length()
  while pad > 0 {
    out.write_char(' ')
    pad = pad - 1
  }
  out.to_string()
}

///|
fn format_percent(value : Double) -> String {
  let scaled = (value * 10.0).round().to_int()
  let whole = scaled / 10
  let fraction = scaled % 10
  whole.to_string() + "." + fraction.to_string() + "%"
}
