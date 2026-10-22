# TFLint configuration (https://github.com/terraform-linters/tflint), used by
# the tflint job of the validate stage: Terraform best practices that
# `terraform validate` does not check (unused declarations, pinned module and
# provider versions, typed variables...).
#
# Only the "terraform" ruleset built into the TFLint binary: it needs no
# `tflint --init`, so the job downloads no plugin from GitHub, whose anonymous
# API limit the runner would hit.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
