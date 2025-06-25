terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  backend "gcs" {
    bucket = "ms-cloud-alerts-gcp-tfstate"
    # The prefix will be set dynamically via -backend-config in your CI
  }
  required_version = ">= 1.5.0"
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  # Credentials will be sourced from OIDC/Cloud Shell or environment
}
