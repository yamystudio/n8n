# N8N Kubernetes Deployment and Upgrade

A comprehensive guide for deploying and upgrading N8N in Kubernetes environments.

## Project Structure
```
n8n/
├── README.md                 # This guide
├── n8n-deployment.yaml      # Kubernetes deployment configuration
├── cloudbuild.yaml          # Cloud Build pipeline configuration
├── Dockerfile               # N8N container image configuration
└── scripts/
    └── upgrade-onprem.sh    # On-premise upgrade script
```

## Deployment
Deploy N8N to your Kubernetes cluster:

```bash
kubectl apply -f n8n-deployment.yaml
```

The deployment includes:
- N8N application
- PostgreSQL database
- Persistent volumes
- Service, ingress, secret, configmap

## Upgrade Methods

### 1. N8N Upgrade in GKE (Using Cloud Build)
For N8N deployments in Google Kubernetes Engine environments, you have two options:

#### Option A: Manual Upgrade (Local)
Run the upgrade directly from your terminal:

```bash
# Navigate to the repository root
cd /path/to/n8n

# Upgrade to specific version
gcloud builds submit --config=cloudbuild.yaml \
  --substitutions=_TARGET_N8N_VERSION=1.69.1
```

Configuration variables:
| Variable | Description | Example |
|----------|-------------|---------|
| `_CLUSTER_LOCATION` | GKE cluster location (must specify region or zone based on cluster type) | Region: `europe-west1`<br>Zone: `europe-west1-b` |
| `_CLUSTER_NAME` | Name of the GKE cluster | `n8n-cluster` |
| `_DEPLOYMENT_NAME` | Name of the N8N deployment | `n8n` |
| `_NAMESPACE` | Kubernetes namespace | `n8n` |
| `_PG_SECRET_NAME` | PostgreSQL secret name | `postgres-secret` |
| `_BACKUP_BUCKET` | GCS bucket for backups | `backup-gcs` |
| `_REPO_LOCATION` | Artifact Registry location | `europe-west1` |
| `_TARGET_N8N_VERSION` | Specific N8N version (optional) | `1.69.1` |
| `_AUTO_UPGRADE` | Set to `true` for automatic upgrades; leave empty for manual upgrades | `true` |

#### Option B: Automated Upgrades
For automated upgrades, you'll need to:
1. Fork this repository to your GitHub organization
2. Connect GitHub to Cloud Build
3. Set up Cloud Build trigger and Cloud Scheduler

##### Repository Setup
1. Fork this repository to your GitHub organization
2. Connect GitHub to Cloud Build:
   - Go to [Cloud Build Triggers](https://console.cloud.google.com/cloud-build/triggers)
   - Click "Connect Repository"
   - Select your forked repository
   - Done

##### Cloud Build Setup
1. Create a Cloud Build trigger:
```bash
gcloud builds triggers create manual \
  --name="n8n-auto-upgrade" \
  --repo="https://github.com/[YOUR_ORGANIZATION]/n8n]" \
  --repo-type="GITHUB" \
  --branch="master" \
  --build-config="cloudbuild.yaml" \
  --substitutions="_AUTO_UPGRADE=true" \
  --description="Automated N8N upgrade trigger"
```

2. Set up Cloud Scheduler job:
```bash
# Get your project ID, Number and trigger ID
PROJECT_ID=$(gcloud config get-value project)
TRIGGER_ID=$(gcloud builds triggers describe n8n-auto-upgrade --format='value(id)')
PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')

# Create service account for Cloud Scheduler
gcloud iam service-accounts create n8n-upgrade-scheduler \
  --display-name="N8N Upgrade Scheduler"

# Get the service account email
SERVICE_ACCOUNT="n8n-upgrade-scheduler@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant necessary permissions
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/cloudbuild.builds.editor"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/cloudbuild.builds.approver"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member=serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
    --role=roles/gkebackup.admin

# Create the scheduler job
gcloud scheduler jobs create http n8n-version-check \
  --schedule="0 0 1 * *" \
  --uri="https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/triggers/${TRIGGER_ID}:run" \
  --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform" \
  --message-body="{\"branchName\":\"master\"}" \
  --oauth-service-account-email="${SERVICE_ACCOUNT}" \
  --time-zone="Europe/Istanbul"
```

Note: If you get permission errors, make sure to:
1. Wait a few minutes after creating the service account for permissions to propagate
2. Enable the Cloud Build API and Cloud Scheduler API in your project
3. Verify that the trigger ID is correct

The automated setup will:
- Check for new N8N versions weekly
- Automatically trigger the upgrade process if a new version is available
- Maintain all safety measures and backup procedures

You can customize the schedule using standard cron syntax:
- Weekly: `0 0 * * 1` (Every Monday at 00:00)
- Monthly: `0 0 1 * *` (First day of each month at 00:00)
- Daily: `0 0 * * *` (Every day at 00:00)

### 2. On-Premise Upgrade

> **Note:** The upgrade script is theoretically implemented and not tested yet. Use with caution in production environments.

For self-managed Kubernetes clusters:

```bash
cd /path/to/n8n/scripts

# Show available options
./upgrade-onprem.sh -h

# Upgrade to latest version
./upgrade-onprem.sh

# Upgrade to specific version
./upgrade-onprem.sh -v 1.69.1

# Upgrade in different namespace
./upgrade-onprem.sh -n custom-namespace -v 1.69.1
```

Available flags:
- `-n, --namespace`: Kubernetes namespace (default: n8n)
- `-v, --version`: Target N8N version
- `-d, --deployment`: N8N deployment name (default: n8n)
- `-b, --backup-dir`: Backup directory (default: ./n8n-backups)

## Upgrade Features
- Automatic version detection and compatibility check
- Database and persistent volume backups before upgrade
- Safe deployment with rollback capability
- Node.js version compatibility verification