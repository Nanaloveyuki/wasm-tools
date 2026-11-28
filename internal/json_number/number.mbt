///|
#derive(Eq)
priv struct Decimal {
  negative : Bool
  digits : String
  power : BigInt
}

///|
// Keep the exponent separate so even a very large exponent never expands digits.
fn decimal(text : String) -> Decimal? {
  let exponent_at = match text.find("e") {
    Some(index) => Some(index)
    None => text.find("E")
  }
  let significand_end = exponent_at.unwrap_or(text.length())
  let negative = text.has_prefix("-")
  let start = if negative { 1 } else { 0 }
  let significand = text[start:significand_end]
  let parts = significand.split(".").to_array()
  let fraction = parts.get(1).unwrap_or("")
  let untrimmed = parts[0].to_owned() + fraction.to_owned()
  let nonzero = untrimmed.trim_start(chars="0")
  if nonzero.is_empty() {
    return Some({ negative: false, digits: "", power: BigInt::from_int(0), })
  }
  let digits = nonzero.trim_end(chars="0")
  let exponent = match exponent_at {
    Some(index) => {
      let exponent_text = text[index + 1:]
      let digits_start = if exponent_text.has_prefix("+") { 1 } else { 0 }
      @str.parse_bigint(exponent_text[digits_start:]) catch {
        _ => return None
      }
    }
    None => BigInt::from_int(0)
  }
  let shift = nonzero.length() - digits.length() - fraction.length()
  Some({
    negative,
    digits: digits.to_owned(),
    power: exponent + BigInt::from_int(shift),
  })
}

///|
fn numeric_equal(left : String, right : String) -> Bool {
  left == right ||
  (decimal(left) is Some(a) && decimal(right) is Some(b) && a == b)
}

///|
pub fn nonnegative_int32(value : Json) -> Int32? {
  guard value is Number(number, repr~) &&
    number >= 0.0 &&
    number <= 2147483647.0 else {
    return None
  }
  let integer = number.to_int()
  guard integer.to_double() == number else { return None }
  if repr is Some(text) && !numeric_equal(text, integer.to_string()) {
    return None
  }
  Some(integer)
}

///|
pub fn equal(left : Json, right : Json) -> Bool {
  match (left, right) {
    (Number(_, ..), Number(_, ..)) =>
      numeric_equal(left.stringify(), right.stringify())
    (Array(a), Array(b)) => {
      guard a.length() == b.length() else { return false }
      for index, value in a {
        if !equal(value, b[index]) {
          return false
        }
      }
      true
    }
    (Object(a), Object(b)) => {
      guard a.length() == b.length() else { return false }
      for key, value in a {
        guard b.get(key) is Some(other) && equal(value, other) else {
          return false
        }
      }
      true
    }
    _ => left == right
  }
}
