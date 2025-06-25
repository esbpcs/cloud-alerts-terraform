# -----------------------------------------------------------------------------
# DATA SOURCES
# -----------------------------------------------------------------------------
data "google_secret_manager_secret_version" "slack_token" {
  count   = var.enable_slack_notifications ? 1 : 0
  project = var.gcp_project_id
  secret  = var.root_slack_secret_name
}

# Updated to use specific token auth variables
data "google_secret_manager_secret_version" "webhook_token" {
  count   = var.enable_webhook_token_auth && var.webhook_token_auth_secret_name != null && var.webhook_token_auth_secret_name != "" ? 1 : 0
  project = var.gcp_project_id
  secret  = var.webhook_token_auth_secret_name
}

# Updated to use specific basic auth variables
data "google_secret_manager_secret_version" "webhook_basic_auth_password" {
  count   = var.enable_webhook_basic_auth && var.webhook_basic_auth_password_secret_name != null && var.webhook_basic_auth_password_secret_name != "" ? 1 : 0
  project = var.gcp_project_id
  secret  = var.webhook_basic_auth_password_secret_name
}

# -----------------------------------------------------------------------------
# NOTIFICATION CHANNEL RESOURCES
# -----------------------------------------------------------------------------
resource "google_monitoring_notification_channel" "email" {
  count        = var.enable_email_notifications ? 1 : 0
  project      = var.gcp_project_id
  display_name = "Email Notifications"
  type         = "email"
  labels = {
    email_address = var.root_primary_email_address
  }
}

resource "google_monitoring_notification_channel" "slack" {
  count        = var.enable_slack_notifications ? 1 : 0
  project      = var.gcp_project_id
  display_name = "Slack Notifications"
  type         = "slack"
  labels = {
    channel_name = var.root_slack_channel_name
  }
  sensitive_labels {
    auth_token = data.google_secret_manager_secret_version.slack_token[0].secret_data
  }
}

resource "google_monitoring_notification_channel" "webhook_token_auth" {
  count        = var.enable_webhook_token_auth ? 1 : 0
  project      = var.gcp_project_id
  display_name = "Webhook Notifications (Token Auth)"
  type         = "webhook_tokenauth"

  labels = {
    url = var.webhook_token_auth_url
  }

  sensitive_labels {
    auth_token = var.webhook_token_auth_secret_name != null && var.webhook_token_auth_secret_name != "" ? data.google_secret_manager_secret_version.webhook_token[0].secret_data : ""
  }
}

resource "google_monitoring_notification_channel" "webhook_basic_auth" {
  count        = var.enable_webhook_basic_auth ? 1 : 0
  project      = var.gcp_project_id
  display_name = "Webhook Notifications (Basic Auth)"
  type         = "webhook_basicauth"

  labels = {
    # Dynamically constructs the URL with the username, e.g., "https://user@example.com/path"
    url = "https://${var.webhook_basic_auth_username}@${replace(var.webhook_basic_auth_url, "https://", "")}"
  }

  sensitive_labels {
    # Password is fetched securely from Secret Manager
    password = var.webhook_basic_auth_password_secret_name != null && var.webhook_basic_auth_password_secret_name != "" ? data.google_secret_manager_secret_version.webhook_basic_auth_password[0].secret_data : ""
  }
}

# -----------------------------------------------------------------------------
# LOCAL VARIABLES
# -----------------------------------------------------------------------------
locals {
  # -----------------------------------------------------------------------------
  # 1. Gather policy YAMLs
  # -----------------------------------------------------------------------------
  files_list = fileset("alert_policies", "*.yaml")

  alert_policy_yaml_files = {
    for f in local.files_list : replace(basename(f), ".yaml", "") => "alert_policies/${f}"
  }

  processed_policies_map = {
    for service_key, yaml_file_path in local.alert_policy_yaml_files : service_key => flatten([
      for doc_content in split("\n---\n", file(yaml_file_path)) :
      try(
        yamldecode(trimspace(doc_content)),
        null
      )
      if length(trimspace(doc_content)) > 0 && !can(regex("^[-\\s]*$", trimspace(doc_content)))
    ])
  }

  # -----------------------------------------------------------------------------
  # 2. Build label filter maps per policy+condition
  # -----------------------------------------------------------------------------

  label_filter_map = {
    for service_key, policy_list in local.processed_policies_map : service_key => {
      for policy_object in policy_list : policy_object.display_name => {
        for cond in try(policy_object.conditions, []) : cond.display_name => {
          include = coalesce(
            try(var.alert_label_filters[policy_object.display_name].conditions[cond.display_name].include_labels, null),
            {}
          )
          exclude = coalesce(
            try(var.alert_label_filters[policy_object.display_name].conditions[cond.display_name].exclude_labels, null),
            {}
          )
        }
      }
    }
  }

  # Flatten label_filter_map into a single-level map for lookup by "displayName::condName"
  flat_label_filter_map = {
    for triple in flatten([
      for service_key, per_service in local.label_filter_map : [
        for display_name, conds in per_service : [
          for cond_name, incl_excl in conds : {
            display_name = display_name
            cond_name    = cond_name
            incl_excl    = incl_excl
          }
        ]
      ]
    ]) : "${triple.display_name}::${triple.cond_name}" => triple.incl_excl
  }

  # -----------------------------------------------------------------------------
  # 3. Compose filter strings per policy+condition
  # -----------------------------------------------------------------------------
  label_filter_strings = {
    for pair, incl_excl in local.flat_label_filter_map :
    pair => join(" AND ", compact(concat(
      [
        for k, v in incl_excl.include :
        can(v[0])
        ? format("(%s)", join(" OR ", [for val in v :
          format(
            "%s = \"%s\"",
            (startswith(k, "metric.label.") || startswith(k, "resource.label.")) ? k : format("resource.label.%s", k),
            val
          )
        ]))
        : format(
          "%s = \"%s\"",
          (startswith(k, "metric.label.") || startswith(k, "resource.label.")) ? k : format("resource.label.%s", k),
          v
        )
      ],
      [
        for k, v in incl_excl.exclude :
        can(v[0])
        ? format("(%s)", join(" OR ", [for val in v :
          format(
            "NOT %s = \"%s\"",
            (startswith(k, "metric.label.") || startswith(k, "resource.label.")) ? k : format("resource.label.%s", k),
            val
          )
        ]))
        : format(
          "NOT %s = \"%s\"",
          (startswith(k, "metric.label.") || startswith(k, "resource.label.")) ? k : format("resource.label.%s", k),
          v
        )
      ]
    )))
  }

  # -----------------------------------------------------------------------------
  # 4. Build final alert policies for the modules/resources
  # -----------------------------------------------------------------------------
  all_policies_for_module = flatten([
    for service_key, policy_list in local.processed_policies_map : [
      for policy_object in policy_list : {
        display_name = policy_object.display_name
        enabled      = lookup(var.alert_enablement, policy_object.display_name, try(policy_object.enabled, true))
        combiner     = try(policy_object.combiner, "OR")
        documentation = try(policy_object.documentation, {
          content   = "Alert policy managed by Terraform.",
          mime_type = "text/markdown"
        })
        user_labels = merge(try(policy_object.user_labels, {}), { "service" = service_key })
        conditions = [
          for cond in policy_object.conditions : {
            display_name = try(cond.display_name, "Condition")

            # THRESHOLD condition
            condition_threshold = try(cond.condition_threshold, null) != null && try(cond.condition_threshold.threshold_value, null) != null ? {
              filter = (
                length(lookup(local.label_filter_strings, "${policy_object.display_name}::${cond.display_name}", "")) > 0
                ? (
                  length(trimspace(replace(cond.condition_threshold.filter, "ProjectID", var.gcp_project_id))) > 0
                  ? format(
                    "(%s) AND %s",
                    replace(cond.condition_threshold.filter, "ProjectID", var.gcp_project_id),
                    lookup(local.label_filter_strings, "${policy_object.display_name}::${cond.display_name}", "")
                  )
                  : lookup(local.label_filter_strings, "${policy_object.display_name}::${cond.display_name}", "")
                )
                : replace(cond.condition_threshold.filter, "ProjectID", var.gcp_project_id)
              )
              comparison      = cond.condition_threshold.comparison
              threshold_value = tonumber(cond.condition_threshold.threshold_value)
              duration        = try(var.alert_time_period_overrides[policy_object.display_name].conditions[cond.display_name].duration, cond.condition_threshold.duration)
              trigger         = try(cond.condition_threshold.trigger, null)
              aggregations = [
                for agg in try(cond.condition_threshold.aggregations, []) : {
                  alignment_period     = try(var.alert_time_period_overrides[policy_object.display_name].conditions[cond.display_name].alignment_period, agg.alignment_period)
                  per_series_aligner   = agg.per_series_aligner
                  cross_series_reducer = try(agg.cross_series_reducer, null)
                  group_by_fields      = try(agg.group_by_fields, [])
                }
              ]
              denominator_filter       = try(cond.condition_threshold.denominator_filter, null)
              denominator_aggregations = try(cond.condition_threshold.denominator_aggregations, [])
            } : null

            # ABSENT condition
            condition_absent = try(cond.condition_absent, null) != null ? {
              filter = (
                length(lookup(local.label_filter_strings, "${policy_object.display_name}::${cond.display_name}", "")) > 0
                ? (
                  length(trimspace(replace(cond.condition_absent.filter, "ProjectID", var.gcp_project_id))) > 0
                  ? format(
                    "(%s) AND %s",
                    replace(cond.condition_absent.filter, "ProjectID", var.gcp_project_id),
                    lookup(local.label_filter_strings, "${policy_object.display_name}::${cond.display_name}", "")
                  )
                  : lookup(local.label_filter_strings, "${policy_object.display_name}::${cond.display_name}", "")
                )
                : replace(cond.condition_absent.filter, "ProjectID", var.gcp_project_id)
              )
              duration = try(var.alert_time_period_overrides[policy_object.display_name].conditions[cond.display_name].duration, cond.condition_absent.duration)
              trigger  = try(cond.condition_absent.trigger, null)
              aggregations = [
                for agg in try(cond.condition_absent.aggregations, []) : {
                  alignment_period     = try(var.alert_time_period_overrides[policy_object.display_name].conditions[cond.display_name].alignment_period, agg.alignment_period)
                  per_series_aligner   = agg.per_series_aligner
                  cross_series_reducer = try(agg.cross_series_reducer, null)
                  group_by_fields      = try(agg.group_by_fields, [])
                }
              ]
            } : null

            # LOG BASED
            condition_matched_log = try(cond.condition_matched_log, null) != null ? {
              filter           = replace(cond.condition_matched_log.filter, "ProjectID", var.gcp_project_id)
              label_extractors = try(cond.condition_matched_log.label_extractors, {})
            } : null

            # MQL
            condition_monitoring_query_language = try(cond.condition_monitoring_query_language, null) != null ? {
              query    = replace(cond.condition_monitoring_query_language.query, "ProjectID", var.gcp_project_id)
              duration = try(var.alert_time_period_overrides[policy_object.display_name].conditions[cond.display_name].duration, cond.condition_monitoring_query_language.duration)
              trigger = {
                count   = try(cond.condition_monitoring_query_language.trigger.count, 1)
                percent = try(cond.condition_monitoring_query_language.trigger.percent, null)
              }
              evaluation_missing_data = try(cond.condition_monitoring_query_language.evaluation_missing_data, null)
            } : null
          }
        ]
        alert_strategy = {
          auto_close = coalesce(
            try(policy_object.alert_strategy.auto_close, null),
            try(var.alert_strategy_overrides[policy_object.display_name].auto_close, null),
            var.default_auto_close_duration_seconds
          )
          notification_rate_limit = (
            length([for c in policy_object.conditions : c if try(c.condition_matched_log, null) != null]) > 0
            ? coalesce(
              try(policy_object.alert_strategy.notification_rate_limit, null),
              { period = "300s" }
            )
            : try(policy_object.alert_strategy.notification_rate_limit, null)
          )
        }
      }
      if policy_object != null &&
      try(policy_object.display_name, null) != null &&
      try(policy_object.conditions, null) != null
    ]
  ])

  all_notification_channel_ids = compact(concat(
    var.enable_email_notifications ? [google_monitoring_notification_channel.email[0].id] : [],
    var.enable_slack_notifications ? [google_monitoring_notification_channel.slack[0].id] : [],
    var.enable_webhook_token_auth ? [google_monitoring_notification_channel.webhook_token_auth[0].id] : [],
    var.enable_webhook_basic_auth ? [google_monitoring_notification_channel.webhook_basic_auth[0].id] : [],
    var.additional_notification_channel_ids
  ))
}

# -----------------------------------------------------------------------------
# MODULE BLOCK
# -----------------------------------------------------------------------------
module "alert_policies" {
  source = "./modules"

  for_each = {
    for policy in local.all_policies_for_module :
    policy.display_name => policy
    if policy.enabled && length(policy.conditions) > 0
  }

  policy_config                       = each.value
  monitoring_project_id               = var.gcp_project_id
  global_user_labels                  = var.root_common_user_labels
  notification_channel_ids_for_policy = local.all_notification_channel_ids
}
