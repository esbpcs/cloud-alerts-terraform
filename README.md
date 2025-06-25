# GCP (and beyond) Alerting and Monitoring Framework using Terraform

This repository contains a Terraform-based framework for managing Google Cloud Monitoring resources, including alert policies. It uses a modular approach with YAML definitions for alert policies, includes a validation script for quality assurance, and is designed to be deployed via a GitHub Actions CI/CD workflow.

## Table of Contents

- [Project Overview](#project-overview)
- [Prerequisites](#prerequisites)
- [Directory Structure](#directory-structure)
- [Configuration](#configuration)
  - [Client Configuration (`.tfvars` file)](#client-configuration-tfvars-file)
  - [Example `client_vars/esbpcs.tfvars`](#example-client_varsesbpcstfvars)
- [Notification Channel Configuration](#notification-channel-configuration)
  - [Email and Slack Notifications](#email-and-slack-notifications)
  - [Webhook with Token Authentication](#webhook-with-token-authentication)
  - [Webhook with Basic Authentication](#webhook-with-basic-authentication)
  - [Additional Notification Channel IDs](#additional-notification-channel-ids)
- [Defining and Adding New Alert Policies](#defining-and-adding-new-alert-policies)
  - [YAML File Structure and `service_key`](#yaml-file-structure-and-service_key)
  - [Key YAML Fields for an Alert Policy](#key-yaml-fields-for-an-alert-policy)
  - [Condition Structure](#condition-structure)
  - [Example Alert Policy YAML](#example-alert-policy-yaml)
  - [Steps to Add a New Alert Policy](#steps-to-add-a-new-alert-policy)
  - [Validating Alert Policies](#validating-alert-policies)
  - [Further Information](#further-information)
  - [Using Custom Log-Based Metrics for Alerts](#using-custom-log-based-metrics-for-alerts)
- [Advanced Alert Customization](#advanced-alert-customization)
  - [Time Period Overrides](#time-period-overrides)
  - [Label-Based Filtering](#label-based-filtering)
  - [Alert Strategy Overrides](#alert-strategy-overrides)
  - [Combining Overrides](#combining-overrides)
- [Detailed Alert Policy Reference](#detailed-alert-policy-reference)
- [Deployment (CI/CD Workflow)](#deployment-cicd-workflow)
  - [How to Run the Workflow](#how-to-run-the-workflow)
  - [Workflow Process](#workflow-process)
- [Known Issues and Solutions](#known-issues-and-solutions)
  - [Error: `404 Not Found: Metric Not Available`](#error-404-not-found-metric-not-available)

-----

## Project Overview

The framework consists of four main components:

1. **Terraform Alerting Framework:** Manages the deployment of Google Cloud Monitoring alert policies. Configuration for each client or environment is defined in `.tfvars` files located in the `client_vars/` directory.
2. **Alert Policy Definitions:** A library of alert policies defined as YAML files within the `alert_policies/` directory. Each file focuses on a specific GCP service (e.g., GKE, Pub/Sub, BigQuery).
3. **Policy Validation:** A JSON schema (`alert_policy.schema.json`) and a Python script (`scripts/validate_alert_policies.py`) to ensure all YAML definitions are valid before deployment.
4. **GitHub Actions CI/CD Workflow:** A workflow defined in `gcp-terraform.yml` that automates the deployment process. It authenticates to Google Cloud using Workload Identity Federation and applies the Terraform configuration based on user-selected inputs.

-----

## Prerequisites

- **Terraform:** Version 0.14.x or higher.
- **Google Cloud SDK (`gcloud`):** Required for any manual operations and for setting up the initial environment.
- **Python 3:** Required to run the validation script.
- **GCP Project:** An existing GCP project with **Billing enabled**.
- **Workload Identity Federation:** You must have a Workload Identity Pool and Provider configured in your GCP project to allow GitHub Actions to securely authenticate. The service account used must have the necessary permissions (e.g., Monitoring Admin, Service Usage Admin). A Terraform module to help provision these resources is included in the `gcp-oidc-provisioner/` directory.

-----

## Directory Structure

```bash
.
|-- .github/workflows/
|   |-- gcp-terraform.yml         # GitHub Actions workflow for CI/CD
|-- alert_policies/             # Directory for YAML alert policy definitions
|   |-- app_engine.yaml
|   |-- ... (etc.)
|-- alert_policy.schema.json    # JSON schema for validating alert policies
|-- client_vars/                # Directory for client-specific .tfvars files
|   |-- esbpcs.tfvars
|   |-- ... (etc.)
|-- gcp-oidc-provisioner/       # Terraform module to provision WIF resources
|-- scripts/
|   |-- validate_alert_policies.py # Script to validate YAML files
|   |-- requirements.txt         # Python dependencies for the validation script
|-- main.tf                     # Root Terraform configuration
|-- variables.tf                # Root Terraform variables
|-- outputs.tf                  # Root Terraform outputs
|-- README.md                   # This file
```

-----

## Configuration

Configuration is managed on a per-client (or per-environment) basis using `.tfvars` files. Each deployment, typically representing a specific client or environment (e.g., `staging`, `production`), requires a corresponding `.tfvars` file (e.g., `client_vars/my_environment.tfvars`) located in the `client_vars/` directory.

### Client Configuration (`.tfvars` file)

The following key variables can be defined within each client's `.tfvars` file:

- **`gcp_project_id`**: (String, **Required**) The target Google Cloud project ID.
- **`gcp_region`**: (String, **Required**) The primary GCP region for the resources.
- **`gcp_workload_identity_provider`**: (String, **Required**) The full resource name of your Workload Identity Federation (WIF) provider.
- **`gcp_service_account`**: (String, **Required**) A template string for the service account email that GitHub Actions will impersonate.
- **`root_common_user_labels`**: (Map of strings, Optional) Common labels to apply to all alert policies (e.g., `environment = "prod"`).
- **`alert_enablement`**: (Map of booleans, Optional) A powerful feature to explicitly enable or disable specific alert policies by their full `display_name`. This is useful for new projects where not all services are active, preventing deployment errors for metrics that don't exist yet.
- **Notification Channel Variables**: Refer to the [Notification Channel Configuration](#notification-channel-configuration) section below for a detailed breakdown.
- **Override Variables**: (`alert_time_period_overrides`, `alert_label_filters`, etc.) Refer to the [Advanced Alert Customization](#advanced-alert-customization) section for details.

### Example `client_vars/esbpcs.tfvars`

This example is based on the provided repository context and showcases a real-world configuration.

```terraform
# -----------------------------------------------------------------------------
# CORE CONFIGURATION
# -----------------------------------------------------------------------------
gcp_project_id                 = "your-gcp-project-id"
gcp_region                     = "asia-southeast2"
gcp_workload_identity_provider = "projects/your-project-number/locations/global/workloadIdentityPools/your-pool/providers/your-provider"
gcp_service_account            = "your-service-account@${gcp_project_id}.iam.gserviceaccount.com"

# -----------------------------------------------------------------------------
# NOTIFICATION CHANNEL CONFIGURATION
# -----------------------------------------------------------------------------
enable_email_notifications = true
root_primary_email_address = "your-alerts-email@example.com"

enable_slack_notifications = true
root_slack_channel_name    = "#your-alerts-channel"
root_slack_secret_name     = "your-slack-secret-name"

# --- Webhook with Token Authentication ---
enable_webhook_token_auth = true
webhook_token_auth_url    = "[https://your-webhook-url.site/endpoint](https://your-webhook-url.site/endpoint)"
# webhook_token_auth_secret_name = "your-webhook-token-secret" # (Optional)

# --- Webhook with Basic Authentication ---
enable_webhook_basic_auth = false
# webhook_basic_auth_url                    = "[example.com/handler](https://example.com/handler)"
# webhook_basic_auth_username               = "my-webhook-user"
# webhook_basic_auth_password_secret_name = "my-webhook-password-secret"

# -----------------------------------------------------------------------------
# COMMON AND ADVANCED LABELS
# -----------------------------------------------------------------------------
root_common_user_labels = {
  client_name = "esbp-consulting"
  environment = "staging"
  team        = "cloudops"
  managed_by  = "terraform"
}

# -----------------------------------------------------------------------------
# ALERT POLICY ENABLEMENT
# Only enable alerts for services that are actively in use.
# -----------------------------------------------------------------------------
alert_enablement = {
  # --- SAFE DEFAULTS ---
  "GCE: Instance Down (Critical)"               = true
  "GCE: High CPU Utilization (Warning)"       = true
  "GCS: IAM Policy Change Detected (Critical)"  = true

  # --- ALERTS REQUIRING OPS AGENT ---
  "GCE: High Memory Utilization (Critical)" = false # Enable if Ops Agent is installed
  "GCE: Low Disk Space (Warning)"           = false # Enable if Ops Agent is installed

  # --- ENABLE AS NEEDED ---
  "Load Balancer: High Backend 5xx Error Rate (Critical)" = false
  "Pub/Sub: High Unacknowledged Messages (Critical)"      = false
  # ... and so on for other alerts
}
```

-----

## Notification Channel Configuration

This module can create and manage several types of notification channels. Your configuration file shows support for multiple webhook types.

### Email and Slack Notifications

- `enable_email_notifications`: (Boolean) Set to `true` to enable email notifications.
- `root_primary_email_address`: (String) The destination email address.
- `enable_slack_notifications`: (Boolean) Set to `true` to enable Slack notifications.
- `root_slack_channel_name`: (String) The Slack channel name (e.g., `#gcp-alerts`).
- `root_slack_secret_name`: (String) The name of the Secret Manager secret containing the Slack OAuth token.

### Webhook with Token Authentication

This sends a simple token in the `Authorization` header.

- `enable_webhook_token_auth`: (Boolean) Set to `true` to enable this webhook type.
- `webhook_token_auth_url`: (String) The URL for the webhook endpoint.
- `webhook_token_auth_secret_name`: (String, Optional) The name of a secret in Secret Manager. Its value will be sent as a **Bearer Token**.

### Webhook with Basic Authentication

This sends a username and password.

- `enable_webhook_basic_auth`: (Boolean) Set to `true` to enable this webhook type.
- `webhook_basic_auth_url`: (String) The URL for the webhook endpoint.
- `webhook_basic_auth_username`: (String) The username for Basic Authentication.
- `webhook_basic_auth_password_secret_name`: (String) The name of a secret in Secret Manager containing the password for the specified user.

### Additional Notification Channel IDs

- `additional_notification_channel_ids`: (`list(string)`) A list of pre-existing notification channel resource IDs to add to all alerts. This is useful for integrating with services like PagerDuty that provide a pre-configured channel URL.

-----

## Defining and Adding New Alert Policies

Alert policies in this framework are defined in YAML files located within the `alert_policies/` directory.

### YAML File Structure and `service_key`

- Each `.yaml` file can contain one or more alert policy definitions, separated by `---`.
- When you map a YAML file in your `.tfvars` using `alert_policy_yaml_files`, the key you assign (e.g., `"app_engine"`) serves as a `service_key`.
- This `service_key` is automatically added as a `service` label (e.g., `service: app_engine`) to all alert policies defined in that file.

### Key YAML Fields for an Alert Policy

- `display_name`: (String, **Mandatory**) The human-readable name for the alert policy.
- `enabled`: (Boolean, Optional, Default: `true`) Set to `false` to disable the policy.
- `combiner`: (String, Optional, Default: `"OR"`) How to combine multiple conditions (`"OR"` or `"AND"`).
- `documentation`: (Object, Optional) Provides additional information for the alert notification.
- `user_labels`: (Map, Optional) Custom labels (key-value pairs) to attach to the alert policy.
- `conditions`: (List, **Mandatory**) A list of one or more condition objects that trigger the alert.
- `alert_strategy`: (Object, Optional) Defines the behavior for incidents created by this policy.

### Condition Structure

Each item in the `conditions` list has a `display_name` and one of the following condition types:

- `condition_threshold`: Triggers when a metric crosses a defined threshold.
- `condition_absent`: Triggers when data is not seen for a specified metric.
- `condition_matched_log`: Triggers when a log message matching a specific filter is found.
- `condition_monitoring_query_language`: Triggers based on a custom Monitoring Query Language (MQL) query.

### Example Alert Policy YAML

```yaml
# alert_policies/my_custom_service.yaml
display_name: "High CPU Utilization - My Custom Service"
enabled: true
combiner: "OR"
documentation:
  content: |
    This alert triggers when the CPU utilization for `my-custom-service`
    exceeds 80% for 5 minutes.

    **Troubleshooting:**
    - Check for recent deployments.
    - Analyze instance performance metrics.
  mime_type: "text/markdown"
user_labels:
  severity: "critical"
  owner_team: "backend_services"
conditions:
  - display_name: "CPU Utilization > 80%"
    condition_threshold:
      filter: 'metric.type="compute.googleapis.com/instance/cpu/utilization" resource.type="gce_instance" AND project="ProjectID"'
      comparison: "COMPARISON_GT"
      threshold_value: 0.8
      duration: "300s"
      aggregations:
        - alignment_period: "60s"
          per_series_aligner: "ALIGN_MEAN"
      trigger:
        count: 1
alert_strategy:
  auto_close: "604800s" # 7 days
```

### Steps to Add a New Alert Policy

1. **Choose or Create YAML File:** Decide if the policy belongs in an existing service file or a new one.
2. **Define the Policy in YAML:** Write the policy definition using the fields described above.
3. **Validate the Policy:** Run the local validation script to check for correctness (see below).
4. **Update `.tfvars` (if new file):** Add your new YAML file to the `alert_policy_yaml_files` map.
5. **Apply Configuration:** Run `terraform apply` (typically via the CI/CD workflow) to deploy.

### Validating Alert Policies

To ensure that all YAML alert policies are correctly formatted and adhere to the required structure, a validation script is provided.

- **Schema:** `alert_policy.schema.json` defines the valid structure for an alert policy YAML file.
- **Validation Script:** `scripts/validate_alert_policies.py` checks all `.yaml` files in the `alert_policies/` directory against the schema.

Before committing changes, run the validation script locally:

```bash
# From the root of the repository

# First, install the required Python packages
pip install -r scripts/requirements.txt

# Then, run the validation script
python3 scripts/validate_alert_policies.py
```

### Further Information

For the most detailed and up-to-date information, refer to the [official Google Cloud Monitoring documentation on alert policies](https://cloud.google.com/monitoring/alerts/defining-alert-policies).

### Using Custom Log-Based Metrics for Alerts

You can create **Custom Log-Based Metrics** in Google Cloud to count log entries that match a filter. These can then be used in alert policies.

-----

## Advanced Alert Customization

Override default behaviors in your `.tfvars` file without editing the base YAML.

### Time Period Overrides

- **Variable:** `alert_time_period_overrides`
- **Purpose:** Adjust the `duration` and `alignment_period` for specific conditions to change alert sensitivity for different environments.

### Label-Based Filtering

- **Variable:** `alert_label_filters`
- **Purpose:** Refine the scope of `condition_threshold` and `condition_absent` alerts by including or excluding resources based on their GCP labels. The "Key Grouping/Filtering Labels" column in the table below lists the exact labels you can use for this purpose.

### Alert Strategy Overrides

- **Variable:** `alert_strategy_overrides`
- **Purpose:** Override the `auto_close` duration for specific alert policies.

### Combining Overrides

You can apply multiple overrides (time period, label filters, etc.) to the same policy and condition.

### Detailed Alert Policy Reference

This table provides a detailed breakdown of every alert policy. You can override the default values in your `.tfvars` file. The `Key Grouping/Filtering Labels` column is especially important for using the `alert_label_filters` variable.

| Service | Alert Count | Severity | Alert Policy Display Name | Key Grouping/Filtering Labels | Default Threshold | Default Duration (Alerts After) | Condition Type |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **App Engine** | 4 | Critical | App Engine: High Server Error Rate (Critical) | `resource.project_id` | > 1% Error Ratio | 10m | `condition_monitoring_query_language` |
| | | Warning | App Engine Flex: High CPU Utilization (Warning) | `resource.label.service_id`, `resource.label.version_id` | > 80% | 10m | `condition_threshold` |
| | | Critical | App Engine: High Memory Usage (Critical) | `resource.label.service_id`, `resource.label.version_id` | > 90% | 5m | `condition_threshold` |
| | | Critical | App Engine: No Instances Running (Critical) | `resource.label.service_id`, `resource.label.version_id` | < 1 Instance | 5m | `condition_threshold` |
| **BigQuery** | 5 | Warning | BigQuery: Slow Query Execution (Warning) | `metric.label.user_email` | > 120,000 ms (P99) | 10m | `condition_threshold` |
| | | Critical | BigQuery: Slow Query Execution (Critical) | `metric.label.user_email` | > 300,000 ms (P99) | 5m | `condition_threshold` |
| | | Critical | BigQuery: Failed Queries Detected (Critical) | `metric.label.user_email` | > 0 Queries | 10m | `condition_threshold` |
| | | Warning | BigQuery: High Number of In-Flight Jobs (Warning) | (Project-level) | > 80 Jobs | 5m | `condition_threshold` |
| | | Warning | BigQuery: Excessive Bytes Scanned by User (Warning) | `metric.label.user_email` | > 1 TB | 1h | `condition_threshold` |
| **Bigtable** | 7 | Warning | Bigtable: High CPU Load (Warning) | `resource.label.instance`, `resource.label.cluster` | > 70% | 15m | `condition_threshold` |
| | | Critical | Bigtable: High CPU Load (Critical) | `resource.label.instance`, `resource.label.cluster` | > 90% (Hottest Node) | 5m | `condition_threshold` |
| | | Warning | Bigtable: High Server Latency (Warning) | `resource.label.instance`, `resource.label.cluster`, `resource.label.table` | > 50 ms (P99) | 10m | `condition_threshold` |
| | | Critical | Bigtable: High Replication Latency (Critical) | `resource.label.instance`, `resource.label.cluster` | > 30,000 ms (P99) | 5m | `condition_threshold` |
| | | Critical | Bigtable: Server Errors Detected (Critical) | `resource.label.instance`, `resource.label.cluster`, `resource.label.table` | > 0 Errors | 5m | `condition_threshold` |
| | | Critical | Bigtable: Cluster Has No Nodes (Critical) | `resource.label.instance`, `resource.label.cluster` | < 1 Node | 10m | `condition_threshold` |
| | | Warning | Bigtable: High Storage Utilization (Warning) | `resource.label.instance`, `resource.label.cluster` | > 70% | 1h | `condition_threshold` |
| **Cloud Functions** | 4 | Warning | Cloud Functions: High Execution Error Rate (Warning) | `resource.label.function_name`, `resource.label.region` | Severity = "ERROR" | N/A | `condition_matched_log` |
| | | Critical | Cloud Functions: High Execution Failures (Critical) | `resource.label.function_name`, `resource.label.region` | > 5 Errors | 5m | `condition_threshold` |
| | | Warning | Cloud Functions: High Execution Time (Warning) | `resource.label.function_name`, `resource.label.region` | > 45s (P99) | 5m | `condition_threshold` |
| | | Critical | Cloud Functions: High Memory Usage (Critical) | `resource.label.function_name`, `resource.label.region` | > 460 MB (P99) | 10m | `condition_threshold` |
| **Cloud NAT** | 3 | Critical | Cloud NAT: Allocation Failed (Critical) | `resource.label.gateway_name` | > 0 Failures | 5m | `condition_threshold` |
| | | Warning | Cloud NAT: High Port Usage (Warning) | `resource.label.gateway_name` | > 80% | 15m | `condition_threshold` |
| | | Critical | Cloud NAT: Dropped Packets Detected (Critical) | `resource.label.gateway_name` | > 0 Packets | 5m | `condition_threshold` |
| **Cloud Run** | 4 | Critical | Cloud Run Job: Execution Failed (Critical) | `resource.label.job_name`, `resource.label.location` | > 0 Executions | 5m | `condition_threshold` |
| | | Warning | Cloud Run Job: Long Execution Time (Warning) | `resource.label.job_name`, `resource.label.location` | > 30m (P95) | 10m | `condition_threshold` |
| | | Warning | Cloud Run Job: High Memory Utilization (Warning) | `resource.label.job_name`, `resource.label.location` | > 90% (P95) | 5m | `condition_threshold` |
| | | Warning | Cloud Run Job: High CPU Utilization (Warning) | `resource.label.job_name`, `resource.label.location` | > 90% (P95) | 5m | `condition_threshold` |
| **Cloud SQL** | 4 | Critical | Cloud SQL: Instance Down (Critical) | `resource.label.database_id` | < 1 (Not 'up') | 10m | `condition_threshold` |
| | | Warning | Cloud SQL: High CPU Utilization (Warning) | `resource.label.database_id` | > 80% | 15m | `condition_threshold` |
| | | Critical | Cloud SQL: High Memory Utilization (Critical) | `resource.label.database_id` | > 95% | 10m | `condition_threshold` |
| | | Warning | Cloud SQL: Low Disk Space (Warning) | `resource.label.database_id` | > 80% | 1h | `condition_threshold` |
| **Cloud Spanner** | 3 | Warning | Spanner: High CPU Utilization - REGIONAL (Warning) | `resource.label.instance_id` | > 65% | 15m | `condition_threshold` |
| | | Warning | Spanner: High API Latency (Warning) | `resource.label.instance_id`, `metric.label.method` | > 1000 ms (P99) | 10m | `condition_threshold` |
| | | Warning | Spanner: High Storage Utilization (Warning) | `resource.label.instance_id` | > 75% | 1h | `condition_threshold` |
| **Compute Engine**| 6 | Critical | GCE: Instance Down (Critical) | `resource.label.instance_id`, `resource.label.zone` | No uptime data | 10m | `condition_absent` |
| | | Warning | GCE: High CPU Utilization (Warning) | `resource.label.instance_id`, `resource.label.zone` | > 80% | 15m | `condition_threshold` |
| | | Critical | GCE: High Memory Utilization (Critical) | `resource.label.instance_id`, `resource.label.zone` | > 95% | 10m | `condition_threshold` |
| | | Warning | GCE: Low Disk Space (Warning) | `resource.label.instance_id`, `resource.label.zone`, `metric.label.device` | > 80% | 1h | `condition_threshold` |
| | | Critical | GCE Shielded VM: Boot Integrity Failure (Critical) | `resource.label.instance_id`, `resource.label.zone` | < 1 (Not 'success') | 5m | `condition_threshold` |
| | | Warning | GCE: High Network Received Bytes (Warning) | `resource.label.instance_id`, `resource.label.zone` | > 100 MB/s | 5m | `condition_threshold` |
| **Dataproc** | 4 | Critical | Dataproc: Job Failed (Critical) | `resource.label.cluster_name`, `resource.label.region` | > 0 Jobs | 5m | `condition_threshold` |
| | | Critical | Dataproc: Node Failed (Critical) | `resource.label.cluster_name`, `resource.label.region` | > 0 Nodes | 10m | `condition_threshold` |
| | | Warning | Dataproc: High HDFS Storage Utilization (Warning) | `resource.label.cluster_name`, `resource.label.region` | > 80% | 30m | `condition_threshold` |
| | | Warning | Dataproc: High Pending YARN Memory (Warning) | `resource.label.cluster_name`, `resource.label.region` | > 10 GB | 15m | `condition_threshold` |
| **Filestore** | 5 | Warning | Filestore: Low Disk Space (Warning) | `resource.label.instance_name`, `resource.label.zone` | > 80% | 1h | `condition_threshold` |
| | | Critical | Filestore: Low Disk Space (Critical) | `resource.label.instance_name`, `resource.label.zone` | > 90% | 10m | `condition_threshold` |
| | | Warning | Filestore: Low Inode Count (Warning) | `resource.label.instance_name`, `resource.label.zone` | > 85% | 1h | `condition_threshold` |
| | | Warning | Filestore: High Max Write Latency (Warning) | `resource.label.instance_name`, `resource.label.zone` | > 100 ms | 15m | `condition_threshold` |
| | | Warning | Filestore: High Max Read Latency (Warning) | `resource.label.instance_name`, `resource.label.zone` | > 100 ms | 15m | `condition_threshold` |
| **GCS** | 3 | Critical | GCS: IAM Policy Change Detected (Critical) | `bucket_name`, `method`, `principal` | IAM Policy Change | N/A | `condition_matched_log` |
| | | Critical | GCS: High Server Error Rate (Critical) | `resource.bucket_name` | > 1% Error Ratio | 10m | `condition_monitoring_query_language` |
| | | Warning | GCS: High P99 Total Latency (Warning) | `resource.label.bucket_name`, `metric.label.method` | > 2000 ms (P99) | 15m | `condition_threshold` |
| **GKE** | 6 | Critical | GKE: Container Constantly Restarting (Critical) | `resource.label.cluster_name`, `resource.label.namespace_name`, `resource.label.pod_name`, `resource.label.container_name` | > 5/hour | 15m | `condition_threshold` |
| | | Warning | GKE: Container CPU Throttling (Warning) | `resource.label.cluster_name`, `resource.label.namespace_name`, `resource.label.pod_name`, `resource.label.container_name` | > 85% | 15m | `condition_threshold` |
| | | Warning | GKE: Container Memory Nearing Limit (Warning) | `resource.label.cluster_name`, `resource.label.namespace_name`, `resource.label.pod_name`, `resource.label.container_name` | > 85% | 15m | `condition_threshold` |
| | | Critical | GKE: Node Not Ready (Critical) | `resource.label.cluster_name`, `resource.label.node_name` | No 'Ready' status | 15m | `condition_absent` |
| | | Warning | GKE: High Node CPU Saturation (Warning) | `resource.label.cluster_name` | > 85% | 30m | `condition_threshold` |
| | | Warning | GKE: Persistent Volume Low Disk Space (Warning) | `resource.label.cluster_name`, `resource.label.namespace_name`, `resource.label.pod_name`, `metric.label.volume_name` | > 80% | 1h | `condition_threshold` |
| **Load Balancer** | 2 | Critical | Load Balancer: High Backend 5xx Error Rate (Critical) | `resource.forwarding_rule_name` | > 5% Error Ratio | 5m | `condition_monitoring_query_language` |
| | | Warning | Load Balancer: High Backend Latency (Warning) | `resource.label.forwarding_rule_name` | > 2000 ms (P95) | 10m | `condition_threshold` |
| **Cloud DNS** | 3 | Critical | Cloud DNS: Server Failure (SERVFAIL) Rate (Critical) | `resource.label.zone_name` | > 0 Errors | 5m | `condition_threshold` |
| | | Warning | Cloud DNS: High P99 Resolution Latency (Warning) | `resource.label.zone_name` | > 100 ms (P99) | 15m | `condition_threshold` |
| | | Warning | Cloud DNS: High NXDOMAIN Rate (Warning) | `resource.label.zone_name` | > 100/min | 10m | `condition_threshold` |
| **Pub/Sub** | 4 | Warning | Pub/Sub: High Unacknowledged Messages (Warning) | `resource.label.subscription_id` | > 1,000 Messages | 15m | `condition_threshold` |
| | | Critical | Pub/Sub: High Unacknowledged Messages (Critical) | `resource.label.subscription_id` | > 10,000 Messages | 10m | `condition_threshold` |
| | | Critical | Pub/Sub: Oldest Message is Stale (Critical) | `resource.label.subscription_id` | > 1800s (30m) | 5m | `condition_threshold` |
| | | Critical | Pub/Sub: Messages Sent to Dead-Letter Topic (Critical) | `resource.label.subscription_id` | > 0 Messages | 5m | `condition_threshold` |
| **Redis** | 4 | Critical | Redis: High Memory Usage (Critical) | `resource.label.instance_id` | > 90% | 10m | `condition_threshold` |
| | | Critical | Redis: Key Evictions Detected (Critical) | `resource.label.instance_id` | > 0 Keys | 5m | `condition_threshold` |
| | | Warning | Redis: Low Cache Hit Ratio (Warning) | `resource.instance_id` | < 80% Hit Ratio | 15m | `condition_monitoring_query_language` |
| | | Critical | Redis: Blocked Clients Detected (Critical) | `resource.label.instance_id` | > 0 Clients | 2m | `condition_threshold` |

## Deployment (CI/CD Workflow)

The primary method for deployment is through the GitHub Actions workflow defined in `gcp-terraform.yml`.

### How to Run the Workflow

1. Navigate to the **Actions** tab of your GitHub repository.
2. In the left sidebar, click on the **gcp-terraform** workflow.
3. Click the **Run workflow** dropdown button on the right.
4. Fill in the required inputs:
      - **Action to perform**: Choose `apply` to deploy changes or `destroy` to remove them.
      - **Client Name**: Select the client configuration to deploy (e.g., `esbpcs`).
      - **Branch Ref**: Specify a branch, tag, or commit SHA to run against.
5. Click the **Run workflow** button.

### Workflow Process

1. Checks out the specified branch.
2. Parses the selected client's `.tfvars` file.
3. Authenticates to Google Cloud using Workload Identity Federation.
4. Runs `terraform init`, `plan`, and `apply` (or `destroy`).

## Known Issues and Solutions

### Error: `404 Not Found: Metric Not Available`

This occurs when deploying an alert for a metric that has not been generated yet in your GCP project.

- **Cause**: Many GCP metrics are only created after a specific event occurs (e.g., a job fails). Terraform cannot create an alert for a metric that doesn't exist.
- **Solution**:
    1. Temporarily disable the failing alert policy (`enabled: false`).
    2. Run `terraform apply` to deploy the other working policies.
    3. **Crucially, perform actions in GCP to generate the metric data.**
    4. Wait 10-15 minutes for the metric to appear in the **GCP Console -\> Monitoring -\> Metrics Explorer**.
    5. Re-enable the alert policy (`enabled: true`) and run `terraform apply` again.
