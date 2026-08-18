# sg-assignment-iac
IAC Repo for SG Assignment
# Assignment SG IAC

Infrastructure as Code repository for managing Google Cloud resources using Terraform with automated CI/CD workflows via GitHub Actions.

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Google Cloud Resources](#google-cloud-resources)
- [Local Development](#local-development)
- [CI/CD Workflow](#cicd-workflow)
- [GitHub Actions Secrets](#github-actions-secrets)
- [Terraform Commands](#terraform-commands)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Overview

This repository contains Terraform configuration for managing infrastructure in Google Cloud Platform (GCP). It implements Infrastructure as Code best practices with:

- **Multi-environment support**: Separate configurations for `dev`, `staging`, and `prod` environments
- **Automated validation**: Terraform formatting and validation on every pull request
- **CI/CD pipeline**: Automated planning and applying with GitHub Actions
- **Remote state management**: GCS backend for storing Terraform state
- **Workload Identity Federation**: Secure GitHub Actions authentication to GCP using OpenID Connect (OIDC)

## Repository Structure

```
.
|-- .github/
|   `-- workflows/
|       `-- terraform.yml          # GitHub Actions CI/CD workflow
|-- infra/
|   `-- envs/
|       `-- dev/                   # Development environment
|           |-- backend.tf         # GCS backend configuration
|           |-- main.tf            # Provider and locals configuration
|           |-- locals.tf          # Environment-specific variables
|           |-- gke.tf             # Google Kubernetes Engine cluster
|           |-- service.account.tf # Service account for deployments
|           |-- wif.tf             # Workload Identity Federation setup
|           |-- storage.tf         # GCS bucket for state and artifact registry
|           |-- project-services.tf# Google Cloud services enablement
|           `-- output.tf          # Output values
|-- README.md                       # This file
`-- .gitignore                      # Git ignore rules

### File Descriptions

- **backend.tf**: Configures the GCS backend for storing Terraform state with locking support
- **main.tf**: Defines the Google provider configuration and core locals (project ID, environment name, region, etc.)
- **locals.tf**: Contains environment-specific variable definitions
- **gke.tf**: Google Kubernetes Engine cluster configuration
- **service.account.tf**: Service account and IAM bindings for deployment automation
- **wif.tf**: Workload Identity Federation pool and provider for OIDC authentication
- **storage.tf**: GCS bucket for Terraform state and artifact registry
- **project-services.tf**: Enables required Google Cloud APIs
- **output.tf**: Exports important resource values for external consumption

## Prerequisites

### Local Environment

- **Terraform**: >= 1.6.0
- **Google Cloud SDK**: Latest version
- **gcloud CLI**: Configured with appropriate credentials
- **Git**: For version control

### GCP Requirements

- Active Google Cloud Project
- Appropriate IAM permissions for resource creation
- Service account with necessary roles
- GCS bucket for Terraform state (will be created by Terraform)

> **Note on IAM bootstrapping**: The Terraform service account used by CI (`GCP_TERRAFORM_SA`) should **not** be granted `roles/resourcemanager.projectIamAdmin` or similar IAM-policy-modifying roles. Any `google_project_iam_member` / `google_project_iam_binding` resources that grant roles to *other* principals (e.g. the GKE node service account) must be applied once, manually, using a higher-privileged identity (your own `gcloud` user credentials or a dedicated bootstrap admin). Attempting to manage these bindings with the CI service account itself will fail with a `403 Forbidden` on `getIamPolicy`/`setIamPolicy`, since a principal cannot grant permissions it does not itself hold.

### GitHub Repository Secrets

The following secrets must be configured in your repository settings under **Settings â†’ Secrets and variables â†’ Actions**:

| Secret | Value | Description |
|--------|-------|-------------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/dev-github-pool/providers/dev-github-provider` | WIF provider resource name |
| `GCP_TERRAFORM_SA` | `dev-sa-deployer@project-39eb557f-9be4-42ee-b0c.iam.gserviceaccount.com` | Service account email for Terraform |

Replace `PROJECT_NUMBER` with your GCP project number.

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/prabhat1800/assignment-sg-iac.git
cd assignment-sg-iac
```

### 2. Set Up GCP Project

```bash
# Set your project ID
export PROJECT_ID="project-39eb557f-9be4-42ee-b0c"
gcloud config set project $PROJECT_ID

# Enable required APIs
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  storage-api.googleapis.com \
  artifactregistry.googleapis.com
```

### 3. Create Initial GCS Bucket

```bash
# Create the Terraform state bucket (if not using Terraform to create it)
gsutil mb -l us-central1 gs://${PROJECT_ID}-tfstate
```

### 4. Grant Required IAM Roles (one-time, manual)

Before running CI/CD, grant the following roles manually using an account with sufficient privileges (e.g. project Owner/Editor). These cannot be applied by the CI service account itself â€” see [note above](#prerequisites).

```bash
# Terraform deployer service account
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:dev-sa-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/container.developer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:dev-sa-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/compute.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:dev-sa-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

# GKE node service account (default Compute Engine SA, unless a custom one is configured)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"
```

### 5. Deploy Infrastructure

```bash
cd infra/envs/dev

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -out=tfplan

# Apply the configuration
terraform apply tfplan
```

## Google Cloud Resources

This configuration creates and manages the following GCP resources:

### Core Infrastructure

1. **Google Kubernetes Engine (GKE)**
   - Standard cluster named `dev-assignement` with **Node Auto-Provisioning (NAP)** enabled
   - Location: `us-central1` (regional cluster)
   - Node pools are automatically created/scaled by NAP based on workload demand; nodes may briefly show `FailedScheduling` while a new node is provisioned
   - Deletion protection disabled for dev environment

2. **Service Accounts**
   - `dev-sa-deployer`: Used by GitHub Actions for deployment
   - Assigned roles:
     - `roles/container.developer`: Cluster access
     - `roles/container.clusterViewer`: View-only access
     - `roles/compute.admin`: Manage underlying VMs, instance groups, and networks created by GKE
     - `roles/iam.serviceAccountUser`: Required to attach/act as service accounts on node pools
   - **GKE node service account** (default Compute Engine SA or a custom node SA):
     - `roles/artifactregistry.reader`: Required for nodes to pull container images from Artifact Registry
     - `roles/logging.logWriter`, `roles/monitoring.metricWriter`: Recommended for cluster observability

3. **Workload Identity Federation (WIF)**
   - Pool: `dev-github-pool`
   - Provider: `dev-github-provider`
   - Attributes mapped from GitHub Actions:
     - `repository`: Repository name
     - `repository_owner`: Repository owner
     - `ref`: Git reference (branch/tag)
     - `actor`: GitHub Actions actor
   - Condition: Only allows workflows from `prabhat1800` organization

4. **Cloud Storage**
   - **Terraform State Bucket**: `project-39eb557f-9be4-42ee-b0c-tfstate`
     - Stores Terraform state with locking
     - Prefix: `terraform/state/dev`
   - **Artifact Registry**: Docker repository (`gcr-repo`) for container images

5. **API Services**
   - Container API
   - Compute Engine API
   - IAM API
   - IAM Credentials API
   - Security Token Service
   - Cloud Storage API
   - Artifact Registry API

## Local Development

### Environment Configuration

All environment-specific values are defined in `infra/envs/dev/locals.tf`:

```hcl
locals {
  project_id             = "project-39eb557f-9be4-42ee-b0c"
  environment            = "dev"
  region                 = "us-central1"
  gke_cluster_name       = "assignement"
  deployment_sa_name     = "sa-deployer"
  github_organization    = "prabhat1800"
  wif_pool_id            = "github-pool"
  wif_provider_id        = "github-provider"
  artifact_repository_id = "gcr-repo"
}
```

### Working with Terraform

```bash
cd infra/envs/dev

# Format Terraform files
terraform fmt

# Validate configuration
terraform validate

# Show plan
terraform plan

# Apply configuration
terraform apply

# Destroy resources (dev only)
terraform destroy
```

### Backend Configuration

The backend uses GCS for state storage:

```hcl
backend "gcs" {
  bucket = "project-39eb557f-9be4-42ee-b0c-tfstate"
  prefix = "terraform/state/dev"
}
```

To use backend-free initialization (useful for CI validation):

```bash
terraform init -backend=false
```

## CI/CD Workflow

### Workflow Triggers

The GitHub Actions workflow (`terraform.yml`) is triggered on:

1. **Pull Requests**: Validate and plan infrastructure changes
2. **Push to main**: Apply approved changes
3. **Manual Dispatch**: Manually trigger deployment with environment selection

### Workflow Jobs

#### 1. `changes` Job
- Detects which environments have been modified
- Builds a matrix of environments to process
- Outputs matrix and change detection status

#### 2. `fmt-validate` Job
- Runs on pull requests and manual dispatch
- Validates Terraform formatting: `terraform fmt -check`
- Initializes without backend: `terraform init -backend=false`
- Validates configuration: `terraform validate`

#### 3. `plan` Job
- Runs on pull requests after validation passes
- Authenticates to GCP using Workload Identity
- Runs `terraform plan` with output saved as artifact
- Stores plan artifacts for review

#### 4. `apply-dispatch` Job
- Runs on manual workflow dispatch
- Downloads plan from `plan` job
- Applies Terraform configuration

#### 5. `apply-merge` Job
- Runs after merge to main branch
- Finds associated pull request
- Downloads plan artifact from original PR
- Applies the pre-approved plan

### Authentication Flow

The workflow uses GitHub's native OIDC provider for authentication:

```yaml
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    service_account: ${{ secrets.GCP_TERRAFORM_SA }}
```

This eliminates the need for service account keys in repository secrets.

## GitHub Actions Secrets

Configure these secrets in your repository:

### Required Secrets

1. **GCP_WORKLOAD_IDENTITY_PROVIDER**
   - Resource name of the WIF provider
   - Format: `projects/{PROJECT_NUMBER}/locations/global/workloadIdentityPools/dev-github-pool/providers/dev-github-provider`

2. **GCP_TERRAFORM_SA**
   - Service account email for Terraform operations
   - Format: `dev-sa-deployer@{PROJECT_ID}.iam.gserviceaccount.com`

### Setting Up Secrets

1. Go to **Settings â†’ Secrets and variables â†’ Actions**
2. Click **New repository secret**
3. Add each secret with the values from your GCP setup

## Terraform Commands

### Common Commands

```bash
# Initialize Terraform (downloads providers and initializes backend)
terraform init

# Format files according to Terraform standards
terraform fmt -recursive

# Validate configuration syntax
terraform validate

# Show what changes will be made
terraform plan

# Show plan with specific output
terraform plan -out=tfplan

# Apply configuration changes
terraform apply

# Apply without prompting for confirmation
terraform apply -auto-approve

# Destroy all resources
terraform destroy

# Get information about resources
terraform state list
terraform state show <resource>
```

### Useful Options

```bash
# Work in specific directory
terraform -chdir=infra/envs/dev plan

# Show detailed diff
terraform plan -json | jq

# Target specific resource
terraform plan -target=google_container_cluster.assignment

# Exclude specific resource
terraform plan -exclude-resource=google_storage_bucket.tfstate
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Backend State Bucket Not Found

**Error**: `Error: Failed to get existing workspaces: querying Cloud Storage failed: storage: bucket doesn't exist`

**Solution**:
- Ensure the GCS bucket exists: `gsutil ls gs://{BUCKET_NAME}`
- Create bucket if missing: `gsutil mb -l us-central1 gs://{BUCKET_NAME}`
- Verify bucket name matches `backend.tf` configuration

#### 2. GitHub Actions Secret Not Available

**Error**: `the GitHub Action workflow must specify exactly one of "workload_identity_provider" or "credentials_json"`

**Solution**:
- Verify secrets are configured in repository settings
- Check secret names match workflow references
- For pull requests from forks, secrets are not automatically available
- Ensure WIF provider resource exists in GCP

#### 3. Terraform Formatting Issues

**Error**: `terraform fmt -check` fails in CI

**Solution**:
```bash
# Format all files
terraform fmt -recursive infra/

# Format specific directory
terraform fmt infra/envs/dev/
```

#### 4. Invalid Version Constraint

**Error**: `required_version = "value"` - Invalid version constraint

**Solution**:
- Update `main.tf` with valid version constraint
- Example: `required_version = ">=1.6.0"`

#### 5. Duplicate Local Values

**Error**: `Duplicate local value definition`

**Solution**:
- Check for multiple `locals` blocks in configuration
- Consolidate into single `locals.tf` file
- Ensure no duplicate definitions across files

#### 6. Service Account ID Validation

**Error**: `"account_id" doesn't match regexp`

**Solution**:
- Ensure `deployment_sa_name` is not empty
- Service account ID format: `{environment}-{sa_name}`
- Example: `dev-sa-deployer` (minimum 6 characters)

#### 7. Missing IAM Permissions (`403 Forbidden`)

**Error**: `Required 'compute.instanceGroupManagers.get' permission ...` or similar `403` errors during `terraform apply`

**Solution**:
- These occur when the Terraform service account is missing a role needed to manage or read back GKE/Compute resources
- Grant `roles/compute.admin` and `roles/iam.serviceAccountUser` to the Terraform service account (see [Getting Started](#4-grant-required-iam-roles-one-time-manual))
- Re-run `terraform apply`; IAM changes typically propagate within a couple of minutes

#### 8. IAM Policy Changes Fail in CI

**Error**: `Error retrieving IAM policy for project ... 403: The caller does not have permission, forbidden`

**Solution**:
- The CI service account does not have (and should not be granted) permission to modify project IAM policy
- Remove `google_project_iam_member`/`google_project_iam_binding` resources from configuration applied by CI
- Apply these bindings manually, once, using a higher-privileged identity (see [note in Prerequisites](#prerequisites))

#### 9. Image Pull Failures (`ImagePullBackOff` / `403 Forbidden`)

**Error**: `failed to authorize: failed to fetch oauth token ... 403 Forbidden` when pulling from Artifact Registry

**Solution**:
- The GKE node service account (not the Terraform SA) is missing `roles/artifactregistry.reader`
- Grant the role to the node service account (default Compute Engine SA unless a custom one is configured):
  ```bash
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role="roles/artifactregistry.reader"
  ```
- Delete the affected pod to force an immediate retry: `kubectl delete pod -n <namespace> <pod-name>`

### Debugging

Enable Terraform debug logging:

```bash
export TF_LOG=DEBUG
terraform apply
unset TF_LOG
```

Check GCP authentication:

```bash
gcloud auth list
gcloud config get-value project
```

Get cluster credentials and inspect pods:

```bash
gcloud container clusters get-credentials dev-assignement --region us-central1
kubectl get pods --all-namespaces -o wide
kubectl describe pod <pod-name> -n <namespace>
```

## Contributing

### Development Workflow

1. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**:
   - Update Terraform files in `infra/envs/dev/`
   - Follow Terraform naming conventions
   - Add comments for complex logic

3. **Format and validate**:
   ```bash
   terraform fmt -recursive infra/
   terraform validate
   ```

4. **Push and create pull request**:
   ```bash
   git push origin feature/your-feature-name
   ```

5. **CI/CD validation**:
   - GitHub Actions automatically validates formatting
   - Review the terraform plan output
   - Ensure all checks pass before merge

6. **Merge and deploy**:
   - Merge to `main` branch
   - CI/CD applies changes automatically

### Code Style Guidelines

- Use 2 spaces for indentation
- Use descriptive names for resources
- Keep `locals.tf` for environment-specific variables
- Add comments for non-obvious configurations
- Keep resource blocks organized by type

## Additional Resources

- [Terraform Documentation](https://developer.hashicorp.com/terraform/intro)
- [Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Workload Identity Federation](https://cloud.google.com/docs/authentication/workload-identity-federation)
- [GCS Backend Documentation](https://developer.hashicorp.com/terraform/language/settings/backends/gcs)

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review GitHub Actions workflow logs
3. Check Terraform state for detailed resource information
4. Consult GCP documentation for service-specific issues
