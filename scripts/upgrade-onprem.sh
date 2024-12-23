#!/bin/bash

set -e

NAMESPACE="n8n"
BACKUP_DIR="./n8n-backups"
DEPLOYMENT_NAME="n8n"
PG_SECRET_NAME="postgres-secret"
TARGET_VERSION=""

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -n, --namespace     Kubernetes namespace (default: n8n)"
    echo "  -d, --deployment    N8N deployment name (default: n8n)"
    echo "  -b, --backup-dir    Backup directory (default: ./n8n-backups)"
    echo "  -s, --secret        PostgreSQL secret name (default: postgres-secret)"
    echo "  -v, --version       Target N8N version (if not specified, latest will be used)"
    echo "  -h, --help          Display this help message"
    exit 1
}

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -d|--deployment)
            DEPLOYMENT_NAME="$2"
            shift 2
            ;;
        -b|--backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -s|--secret)
            PG_SECRET_NAME="$2"
            shift 2
            ;;
        -v|--version)
            TARGET_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

mkdir -p "$BACKUP_DIR"

echo "Checking kubectl context..."
CURRENT_CONTEXT=$(kubectl config current-context)
echo "Current context: $CURRENT_CONTEXT"
read -p "Continue with this context? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted. Please set the correct kubectl context and try again."
    exit 1
fi

CURRENT_VERSION=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}' | awk -F: '{print $2}')
echo "Current N8N version: $CURRENT_VERSION"

if [ -z "$TARGET_VERSION" ]; then
    echo "No target version specified, checking latest stable version..."
    TARGET_VERSION=$(curl -s https://api.github.com/repos/n8n-io/n8n/releases | \
        grep -m 1 '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')
    if [ -z "$TARGET_VERSION" ]; then
        echo "Error: Could not determine latest stable version"
        exit 1
    fi
fi

echo "Target N8N version: $TARGET_VERSION"

if [ "$CURRENT_VERSION" == "$TARGET_VERSION" ]; then
    echo "N8N is already at version $TARGET_VERSION. No upgrade needed."
    exit 0
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PREFIX="n8n_${CURRENT_VERSION}_to_${TARGET_VERSION}_${TIMESTAMP}"

echo "Taking backups before upgrade..."

echo "Finding PostgreSQL pod..."
PG_POD=$(kubectl get pods -n $NAMESPACE | grep '^postgres-' | awk '{print $1}')
if [ -z "$PG_POD" ]; then
    echo "Error: PostgreSQL pod not found"
    exit 1
fi
echo "Found PostgreSQL pod: $PG_POD"

echo "Getting database credentials..."
DB_USER=$(kubectl get secret $PG_SECRET_NAME -n $NAMESPACE -o jsonpath='{.stringData.POSTGRES_USER}')
DB_NAME=$(kubectl get secret $PG_SECRET_NAME -n $NAMESPACE -o jsonpath='{.stringData.POSTGRES_DB}')

echo "Using database: $DB_NAME with user: $DB_USER"

echo "Creating database backup..."
kubectl exec $PG_POD -n $NAMESPACE -- pg_dump -U $DB_USER $DB_NAME > "$BACKUP_DIR/${BACKUP_PREFIX}_db.sql"

echo "Creating PV data backup..."
echo "Finding N8N pod..."
N8N_POD=$(kubectl get pods -n $NAMESPACE -l service=n8n -o jsonpath='{.items[0].metadata.name}')
if [ -z "$N8N_POD" ]; then
    echo "Error: N8N pod not found"
    exit 1
fi
echo "Found N8N pod: $N8N_POD"

kubectl exec $N8N_POD -n $NAMESPACE -- tar czf - /home/node/.n8n > "$BACKUP_DIR/${BACKUP_PREFIX}_pv.tar.gz"

echo "Backups created successfully:"
echo "- Database: $BACKUP_DIR/${BACKUP_PREFIX}_db.sql"
echo "- PV Data: $BACKUP_DIR/${BACKUP_PREFIX}_pv.tar.gz"

IMAGE_NAME=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}' | awk -F: '{print $1}')

echo "Updating N8N deployment to version $TARGET_VERSION..."
kubectl set image deployment/$DEPLOYMENT_NAME -n $NAMESPACE n8n=$IMAGE_NAME:$TARGET_VERSION

echo "Waiting for deployment to complete..."
kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE

echo "Upgrade completed successfully!"
echo "New N8N version: $TARGET_VERSION"
echo "Please verify that N8N is working correctly by checking the logs:"
echo "kubectl logs -f deployment/$DEPLOYMENT_NAME -n $NAMESPACE"
