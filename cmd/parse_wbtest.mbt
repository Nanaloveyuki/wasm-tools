///|
test "component detection ignores leading comments" {
  inspect(is_component_wat("(component)"), content="true")
  inspect(is_component_wat(";; note\n(component)"), content="true")
  inspect(is_component_wat("(; block (; nested ;) ;)\n(component)"), content="true")
  inspect(is_component_wat("(module)"), content="false")
  inspect(is_component_wat(";; note\n(module)"), content="false")
  inspect(is_component_wat(""), content="false")
  inspect(is_component_wat("NotWat"), content="false")
}
