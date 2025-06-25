variable "monitoring_project_id" {
  description = "The project ID for monitoring resources."
  type        = string
}

variable "policy_config" {
  description = "A single processed alert policy object."
  type        = any # Or a more specific object type if you have one defined
}

variable "global_user_labels" {
  description = "Global user labels to apply to the alert policy."
  type        = map(string)
  default     = {}
}

variable "notification_channel_ids_for_policy" {
  description = "A list of notification channel IDs for this policy."
  type        = list(string)
  default     = []
}