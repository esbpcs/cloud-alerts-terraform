# GCP OIDC Provisioner

This Terraform module provisions the necessary Google Cloud resources for setting up Workload Identity Federation (WIF) using OIDC, allowing services like GitHub Actions to authenticate with Google Cloud.

## Prerequisites

- Google Cloud SDK (`gcloud`) installed and authenticated if running locally.
- Access to Google Cloud Shell or a similar environment with `gcloud` and Terraform installed.
- Appropriate permissions in your GCP project to create Service Accounts, IAM policies, Workload Identity Pools, and Providers.

## Deployment Steps

Follow these steps to deploy the OIDC provisioner:

1. **Prepare TFState Bucket:**
    A GCS bucket is required to store the Terraform state. If you don't have one, create it using the following commands in Google Cloud Shell (adjust names and locations as needed):

    ```bash
    BUCKET_NAME="ms-cloud-alerts-gcp-tfstate" # Or your preferred unique bucket name
    PROJECT_ID="your-gcp-project-id"          # Replace with your GCP project ID
    LOCATION="asia-southeast2"                # Example location: Replace with your preferred GCP region (e.g., "us-central1", "europe-west1")

    gcloud storage buckets create gs://$BUCKET_NAME \
        --project=$PROJECT_ID \
        --location=$LOCATION \
        --public-access-prevention \
        --soft-delete-duration=0 # Set to 0 to disable soft delete if not needed, otherwise choose a duration
    ```

    **Note:** Ensure this bucket name is unique. The `terraform.tfvars` file in this directory may also need to be updated if it references a backend bucket. For this specific module, if you are deploying it standalone and it doesn't have a `backend.tf` configured to use this bucket, this step is for general best practice or if you intend to configure a remote backend for it.

2. **Navigate to the OIDC Provisioner Directory:**
    Upload this `gcp-oidc-provisioner` folder to your Cloud Shell environment (if not already there) and navigate into it:

    ```bash
    cd path/to/gcp-oidc-provisioner
    ```

3. **Modify Variables (Optional):**
    If you need to change any default variables (e.g., project ID, pool ID, provider attributes), you can edit the `terraform.tfvars` file in this directory using the Cloud Shell Editor or your preferred text editor before deployment.

4. **Initialize Terraform:**
    Run the following command to initialize Terraform:

    ```bash
    terraform init
    ```

5. **Apply Terraform Configuration:**
    Run the following command to apply the Terraform configuration and create the resources. Review the plan and confirm when prompted, or use `--auto-approve` if you are sure.

    ```bash
    terraform apply
    ```

    Or, for automatic approval:

    ```bash
    terraform apply --auto-approve
    ```

## Important Operational Notes

### OIDC Resource Deletion Delays

When you run `terraform destroy` to delete the OIDC resources created by this module, please be aware that the underlying Google Cloud Identity Pool and Workload Identity Provider resources can take some time (potentially several minutes or longer) to be fully deleted in the Google Cloud backend.

If you attempt to recreate these resources (e.g., by running `terraform apply` again) shortly after deleting them, you might encounter errors like "entity already exists" or similar, even if the resources no longer appear in the GCP console.

**Recommendation:**

- Wait for a sufficient amount of time (e.g., 5-10 minutes) after running `terraform destroy` before attempting to re-apply the same configuration.
- If you encounter persistent "entity already exists" errors, double-check the GCP console for any lingering resources and ensure they are fully gone before retrying.
