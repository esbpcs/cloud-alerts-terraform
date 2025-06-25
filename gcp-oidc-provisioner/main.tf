# --- Configuration Variables --- #
variable "gcp_project_id" {
  description = "The GCP Project ID where all resources (WIF, SA, and Alerts) will be managed."
  type        = string
}

variable "gcs_bucket_for_tfstate" {
  description = "The name of the GCS bucket to store Terraform state in."
  type        = string
  default     = "ms-cloud-alerts-gcp-tfstate"
}

variable "service_account_id" {
  description = "The desired ID for the new Service Account."
  type        = string
  default     = "github-actions-runner-1"
}

variable "service_account_display_name" {
  description = "The display name for the Service Account."
  type        = string
  default     = "GitHub Actions Runner SA"
}

variable "workload_identity_pool_id" {
  description = "The desired ID for the Workload Identity Pool."
  type        = string
  default     = "github-actions-pool-1"
}

variable "workload_identity_pool_display_name" {
  description = "The display name for the Workload Identity Pool."
  type        = string
  default     = "GitHub Actions WIF Pool"
}

variable "workload_identity_provider_id" {
  description = "The desired ID for the Workload Identity Provider."
  type        = string
  default     = "github-provider-1"
}

variable "workload_identity_provider_display_name" {
  description = "The display name for the Workload Identity Provider."
  type        = string
  default     = "GitHub OIDC Provider"
}

variable "github_repository" {
  description = "Your GitHub repository in 'owner/repository_name' format."
  type        = string
  # Example: "your-github-owner/your-repo-name"
}

variable "terraform_admin_user" {
  description = "The email of a user who needs permission to run this Terraform apply (e.g., 'user:name@example.com'). This user will be granted Service Account Token Creator role."
  type        = string
  default     = null # Set this in a .tfvars file or pass it as a command-line variable
}


# --- Provider Configuration ---
provider "google" {
  project = var.gcp_project_id
}

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      # Use a pessimistic version constraint for stability.
      # This allows updates to patch and minor versions within major version 5.
      version = "~> 6.0"
    }
  }

  # This backend configuration is a best practice and should remain.
  # It stores your Terraform state file in a GCS bucket.
  # Ensure the bucket "ms-cloud-alerts-gcp-tfstate" exists
  # and your Cloud Shell user has permissions to access it.
  backend "gcs" {
    bucket = "ms-cloud-alerts-gcp-tfstate"
    prefix = "github-oidc-gcp" # This is the path or folder to the state file within the bucket
  }
}

# --- Resources ---

# 1. Workload Identity Pool
resource "google_iam_workload_identity_pool" "main" {
  project                   = var.gcp_project_id
  workload_identity_pool_id = var.workload_identity_pool_id
  display_name              = var.workload_identity_pool_display_name
  description               = "Workload Identity Pool for GitHub Actions"
  disabled                  = false
}

# 2. Workload Identity Pool Provider (for GitHub OIDC)
resource "google_iam_workload_identity_pool_provider" "github_oidc" {
  project                            = var.gcp_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.main.workload_identity_pool_id
  workload_identity_pool_provider_id = var.workload_identity_provider_id
  display_name                       = var.workload_identity_provider_display_name
  description                        = "OIDC Provider for GitHub Actions"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  attribute_mapping = {
    "google.subject"       = "assertion.sub",
    "attribute.actor"      = "assertion.actor",
    "attribute.repository" = "assertion.repository"
  }
  attribute_condition = "assertion.repository == '${var.github_repository}'"
}

# 3. Service Account for GitHub Actions to use
resource "google_service_account" "main" {
  project      = var.gcp_project_id
  account_id   = var.service_account_id
  display_name = var.service_account_display_name
  description  = "Service Account for GitHub Actions to deploy Terraform for alerts"
}

# 4. IAM Policy Binding: Allow WIF provider to impersonate the Service Account
resource "google_service_account_iam_member" "wif_user" {
  service_account_id = google_service_account.main.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.main.name}/attribute.repository/${var.github_repository}"
}

# Also grant the WIF provider the ability to create access tokens for the Service Account.
# This is required for the impersonation to work.
resource "google_service_account_iam_member" "wif_token_creator" {
  service_account_id = google_service_account.main.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.main.name}/attribute.repository/${var.github_repository}"
}

# 5. IAM Binding: Grant necessary roles to the Service Account for managing alerts

resource "google_project_iam_member" "sa_monitoring_editor" {
  project = var.gcp_project_id
  role    = "roles/monitoring.editor"
  member  = "serviceAccount:${google_service_account.main.email}"
}

resource "google_project_iam_member" "sa_logging_config_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.configWriter"
  member  = "serviceAccount:${google_service_account.main.email}"
}

resource "google_project_iam_member" "sa_secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.main.email}"
}

resource "google_project_iam_member" "sa_secret_viewer" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.viewer"
  member  = "serviceAccount:${google_service_account.main.email}"
}

# Grant the Service Account permission to manage objects in the GCS state bucket.
# This is required for Terraform to read and write its state file.
resource "google_storage_bucket_iam_member" "sa_storage_object_admin" {
  bucket = var.gcs_bucket_for_tfstate
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.main.email}"
}

# 6. IAM Binding: Grant a specific user permission to impersonate the SA
# This is useful for allowing a developer to run `terraform apply` manually.
resource "google_service_account_iam_member" "admin_token_creator" {
  count              = var.terraform_admin_user != null ? 1 : 0
  service_account_id = google_service_account.main.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = var.terraform_admin_user
}


# --- Outputs ---
output "workload_identity_provider_name_for_actions" {
  description = "The full name of the Workload Identity Provider. Use this for 'gcp_workload_identity_provider' in your client.tfvars."
  value       = google_iam_workload_identity_pool_provider.github_oidc.name
}

output "service_account_email_for_actions" {
  description = "The email address of the created Service Account. Use this for 'gcp_service_account' in your client.tfvars."
  value       = google_service_account.main.email
}
