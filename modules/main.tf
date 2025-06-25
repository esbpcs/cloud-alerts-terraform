resource "google_monitoring_alert_policy" "single_alert_policy" {
  project               = var.monitoring_project_id
  display_name          = var.policy_config.display_name
  combiner              = var.policy_config.combiner
  user_labels           = merge(var.global_user_labels, var.policy_config.user_labels)
  notification_channels = var.notification_channel_ids_for_policy
  enabled               = try(var.policy_config.enabled, true)

  dynamic "conditions" {
    for_each = var.policy_config.conditions
    content {
      display_name = conditions.value.display_name

      dynamic "condition_threshold" {
        for_each = conditions.value.condition_threshold != null ? [conditions.value.condition_threshold] : []
        content {
          filter             = condition_threshold.value.filter
          comparison         = condition_threshold.value.comparison
          threshold_value    = tonumber(condition_threshold.value.threshold_value)
          duration           = condition_threshold.value.duration
          denominator_filter = try(condition_threshold.value.denominator_filter, null)

          dynamic "trigger" {
            for_each = try(condition_threshold.value.trigger, null) != null ? [condition_threshold.value.trigger] : []
            content {
              count   = try(trigger.value.count, null)
              percent = try(trigger.value.percent, null)
            }
          }

          dynamic "aggregations" {
            for_each = try(condition_threshold.value.aggregations, [])
            content {
              alignment_period     = try(aggregations.value.alignment_period, null)
              per_series_aligner   = try(aggregations.value.per_series_aligner, null)
              cross_series_reducer = try(aggregations.value.cross_series_reducer, null)
              group_by_fields      = try(aggregations.value.group_by_fields, [])
            }
          }

          dynamic "denominator_aggregations" {
            for_each = try(condition_threshold.value.denominator_aggregations, [])
            content {
              alignment_period     = try(denominator_aggregations.value.alignment_period, null)
              per_series_aligner   = try(denominator_aggregations.value.per_series_aligner, null)
              cross_series_reducer = try(denominator_aggregations.value.cross_series_reducer, null)
              group_by_fields      = try(denominator_aggregations.value.group_by_fields, [])
            }
          }
        }
      }

      dynamic "condition_absent" {
        for_each = conditions.value.condition_absent != null ? [conditions.value.condition_absent] : []
        content {
          filter   = condition_absent.value.filter
          duration = condition_absent.value.duration

          dynamic "trigger" {
            for_each = try(condition_absent.value.trigger, null) != null ? [condition_absent.value.trigger] : []
            content {
              count   = try(trigger.value.count, 1)
              percent = try(trigger.value.percent, null)
            }
          }

          dynamic "aggregations" {
            for_each = try(condition_absent.value.aggregations, [])
            content {
              alignment_period     = try(aggregations.value.alignment_period, null)
              per_series_aligner   = try(aggregations.value.per_series_aligner, null)
              cross_series_reducer = try(aggregations.value.cross_series_reducer, null)
              group_by_fields      = try(aggregations.value.group_by_fields, [])
            }
          }
        }
      }

      dynamic "condition_matched_log" {
        for_each = conditions.value.condition_matched_log != null ? [conditions.value.condition_matched_log] : []
        content {
          filter           = condition_matched_log.value.filter
          label_extractors = try(condition_matched_log.value.label_extractors, {})
        }
      }

      dynamic "condition_monitoring_query_language" {
        for_each = conditions.value.condition_monitoring_query_language != null ? [conditions.value.condition_monitoring_query_language] : []
        content {
          query    = condition_monitoring_query_language.value.query
          duration = condition_monitoring_query_language.value.duration

          trigger { # MQL trigger is a block, not dynamic if always present based on root module logic
            count   = try(condition_monitoring_query_language.value.trigger.count, 1)
            percent = try(condition_monitoring_query_language.value.trigger.percent, null)
          }
          evaluation_missing_data = try(condition_monitoring_query_language.value.evaluation_missing_data, null)
        }
      }
    }
  }

  dynamic "documentation" {
    for_each = var.policy_config.documentation != null ? [var.policy_config.documentation] : []
    content {
      content   = documentation.value.content
      mime_type = documentation.value.mime_type
    }
  }

  dynamic "alert_strategy" {
    for_each = var.policy_config.alert_strategy != null ? [var.policy_config.alert_strategy] : []
    content {
      auto_close = try(alert_strategy.value.auto_close, null)

      dynamic "notification_rate_limit" {
        for_each = try(alert_strategy.value.notification_rate_limit, null) != null ? [alert_strategy.value.notification_rate_limit] : []
        content {
          period = notification_rate_limit.value.period
        }
      }
    }
  }
}
