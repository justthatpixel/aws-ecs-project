plugin "aws" {
  enabled = true
  version = "0.40.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# This project's resource labels consistently use kebab-case
# (e.g. "fargate-cluster", "threat-composer") — that's the established
# convention throughout, not something worth a disruptive rename for a
# purely stylistic rule.
rule "terraform_naming_convention" {
  enabled = false
}

rule "terraform_documented_variables" {
  enabled = false
}

rule "terraform_documented_outputs" {
  enabled = false
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}

# These are only useful for reusable/published modules that pin their own
# version constraints independently — child modules here are internal to
# this repo and inherit the constraint declared once in root provider.tf.
rule "terraform_required_version" {
  enabled = false
}

rule "terraform_required_providers" {
  enabled = false
}
