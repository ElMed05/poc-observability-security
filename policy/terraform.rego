package terraform.policies
deny[msg] {
  some rc
  rc := input.resource_changes[_]
  rc.type == "helm_release"
  contains(to_string(rc.change.after), ":latest")
  msg := "Policy: Container-Image nutzt :latest — bitte Version taggen."
}
