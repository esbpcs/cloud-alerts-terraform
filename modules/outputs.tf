output "alert_policy_id" {
  description = "The ID of the created alert policy."
  value       = google_monitoring_alert_policy.single_alert_policy.id
}

output "alert_policy_name" {
  description = "The name of the created alert policy."
  value       = google_monitoring_alert_policy.single_alert_policy.name
}