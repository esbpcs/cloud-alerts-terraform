# ------------------------------------------------------------------------------
# CORE INFRASTRUCTURE CONFIGURATION
#
# These variables define the fundamental GCP project and region for the deployment.
# ------------------------------------------------------------------------------

variable "gcp_project_id" {
  type        = string
  description = "GCP project ID for resource deployment."
}

variable "gcp_region" {
  type        = string
  description = "GCP region for resource deployment."
}

variable "gcp_workload_identity_provider" {
  type        = string
  description = "Workload Identity Provider for CI/CD authentication. This value is read by the GitHub Actions workflow."
  default     = null
}

# ------------------------------------------------------------------------------
# GLOBAL ALERT SETTINGS
#
# These variables apply globally to all created alert policies.
# ------------------------------------------------------------------------------

variable "root_common_user_labels" {
  type        = map(string)
  description = "Common user labels (e.g., environment, team) for all alert policies."
}

variable "default_auto_close_duration_seconds" {
  type        = string
  description = "Default auto-close duration for alert incidents, e.g., '259200s' for 3 days."
  default     = "86400s" # 1 day
}

# ------------------------------------------------------------------------------
# NOTIFICATION CHANNEL TOGGLES & DETAILS
#
# Settings for each type of notification channel.
# ------------------------------------------------------------------------------

variable "additional_notification_channel_ids" {
  type        = list(string)
  description = "List of other pre-existing notification channel IDs to add to all alerts."
  default     = []
}

# --- Email Notifications ---
variable "enable_email_notifications" {
  type        = bool
  description = "Enable the email notification channel?"
  default     = false
}

variable "root_primary_email_address" {
  type        = string
  description = "Email address for the email notification channel."
  default     = null
}

# --- Slack Notifications ---
variable "enable_slack_notifications" {
  type        = bool
  description = "Enable the Slack notification channel?"
  default     = false
}

variable "root_slack_channel_name" {
  type        = string
  description = "Slack channel name for notifications (e.g., #gcp-alerts)."
  default     = null
}

variable "root_slack_secret_name" {
  type        = string
  description = "Secret Manager name for the Slack OAuth token."
  default     = null
}

# --- Webhook with Token Authentication ---
variable "enable_webhook_token_auth" {
  type        = bool
  description = "Enable the webhook that uses a simple token for authentication?"
  default     = false
}

variable "webhook_token_auth_url" {
  type        = string
  description = "URL for the token-based webhook notification channel."
  default     = null
  validation {
    condition     = var.webhook_token_auth_url == null || can(regex("^https?://", var.webhook_token_auth_url))
    error_message = "webhook_token_auth_url must be a valid HTTP or HTTPS URL."
  }
}

variable "webhook_token_auth_secret_name" {
  type        = string
  description = "Secret Manager name for the token-based webhook's auth token."
  default     = null
}


# --- Webhook with Basic Authentication ---
variable "enable_webhook_basic_auth" {
  type        = bool
  description = "Enable the webhook that uses username/password for authentication?"
  default     = false
}

variable "webhook_basic_auth_url" {
  type        = string
  description = "URL for the Basic Auth webhook (e.g., example.com/handler)."
  default     = null
  validation {
    condition     = var.webhook_basic_auth_url == null || can(regex("^https?://", var.webhook_basic_auth_url))
    error_message = "webhook_basic_auth_url must be a valid HTTP or HTTPS URL."
  }
}

variable "webhook_basic_auth_username" {
  type        = string
  description = "The plain text username for the Basic Auth webhook."
  default     = null
}

variable "webhook_basic_auth_password_secret_name" {
  type        = string
  description = "Secret Manager name for the Basic Auth webhook's password."
  default     = null
}


# ------------------------------------------------------------------------------
# ALERT POLICY CUSTOMIZATION & OVERRIDES
#
# These variables allow for fine-grained control over the alert policies.
# ------------------------------------------------------------------------------

variable "alert_enablement" {
  type        = map(bool)
  description = "A map to explicitly enable or disable alert policies by their display_name."
  default     = {}
}

variable "alert_strategy_overrides" {
  type = map(object({
    auto_close = optional(string)
  }))
  description = "Overrides the 'auto_close' duration for specific alert policies. The key is the alert's display_name."
  default     = {}
  validation {
    condition = alltrue([
      for policy_name, strategy_config in var.alert_strategy_overrides :
      (
        policy_name != "" &&
        (strategy_config.auto_close == null || regex("^[1-9]\\d*s$", strategy_config.auto_close))
      )
    ])
    error_message = "Invalid 'alert_strategy_overrides': Policy names must be non-empty and 'auto_close' must be a string of seconds (like '300s')."
  }
}

variable "alert_time_period_overrides" {
  type = map(object({
    conditions = optional(map(object({
      duration         = optional(string)
      alignment_period = optional(string)
    })))
  }))
  description = "Overrides the duration and alignment_period for specific alert policy conditions."
  default     = {}
}

variable "alert_label_filters" {
  type = map(object({
    conditions = optional(map(object({
      include_labels = optional(map(any))
      exclude_labels = optional(map(any))
    })))
  }))
  description = <<EOT
A map to specify label-based filters for alert policy conditions.
The key is the alert's display_name, followed by the condition's display_name.
- 'include_labels': matched resources must have these labels.
- 'exclude_labels': matched resources must NOT have these labels.
Each label value can be a string or a list of strings.
EOT
  default     = {}
}
