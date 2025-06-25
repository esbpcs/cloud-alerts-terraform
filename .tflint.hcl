# This block tells TFLint to enable the Google Cloud plugin, which
# allows it to understand and lint GCP-specific resources.
plugin "google" {
    enabled = true
    version = "0.32.0"
    source  = "github.com/terraform-linters/tflint-ruleset-google"
}

# This rule disables the "unused variable" warning, as we discussed.
rule "terraform_unused_declarations" {
  enabled = false
}