#!/bin/bash
# =============================================================================
# Deployment Script for Robust Data Processor
# =============================================================================
# 
# Prerequisites:
# 1. Google Cloud SDK installed: https://cloud.google.com/sdk/docs/install
# 2. Logged in: gcloud auth login
# 3. Billing enabled on your project
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh your-project-id us-central1
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: Project ID required${NC}"
    echo "Usage: ./deploy.sh <project-id> [region]"
    exit 1
fi

PROJECT_ID=$1
REGION=${2:-us-central1}
TOPIC_ID="ingest-topic"
SUBSCRIPTION_ID="ingest-subscription"

echo -e "${GREEN}=== Deploying to GCP ===${NC}"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# Set project
echo -e "${YELLOW}Setting active project...${NC}"
gcloud config set project $PROJECT_ID

# Enable APIs
echo -e "${YELLOW}Enabling required APIs...${NC}"
gcloud services enable \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    pubsub.googleapis.com \
    firestore.googleapis.com \
    --quiet

# Create Firestore database (if not exists)
echo -e "${YELLOW}Creating Firestore database...${NC}"
gcloud firestore databases create --location=$REGION --quiet 2>/dev/null || echo "Firestore already exists"

# Create Pub/Sub topic (if not exists)
echo -e "${YELLOW}Creating Pub/Sub topic...${NC}"
gcloud pubsub topics create $TOPIC_ID --quiet 2>/dev/null || echo "Topic already exists"

# Deploy API service
echo -e "${YELLOW}Deploying API service...${NC}"
cd api
gcloud run deploy ingest-api \
    --source . \
    --platform managed \
    --region $REGION \
    --allow-unauthenticated \
    --set-env-vars "GCP_PROJECT_ID=$PROJECT_ID,PUBSUB_TOPIC_ID=$TOPIC_ID" \
    --quiet

API_URL=$(gcloud run services describe ingest-api --region $REGION --format="value(status.url)")
echo -e "${GREEN}API deployed at: $API_URL${NC}"

# Deploy Worker service
echo -e "${YELLOW}Deploying Worker service...${NC}"
cd ../worker
gcloud run deploy ingest-worker \
    --source . \
    --platform managed \
    --region $REGION \
    --no-allow-unauthenticated \
    --set-env-vars "GCP_PROJECT_ID=$PROJECT_ID" \
    --timeout=300 \
    --quiet

WORKER_URL=$(gcloud run services describe ingest-worker --region $REGION --format="value(status.url)")
echo -e "${GREEN}Worker deployed at: $WORKER_URL${NC}"

# Get service account for push authentication
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
SERVICE_ACCOUNT="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"

# Grant invoker role to Pub/Sub service account
echo -e "${YELLOW}Granting Pub/Sub permission to invoke Worker...${NC}"
gcloud run services add-iam-policy-binding ingest-worker \
    --region $REGION \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/run.invoker" \
    --quiet

# Create Pub/Sub subscription (if not exists)
echo -e "${YELLOW}Creating Pub/Sub subscription...${NC}"
gcloud pubsub subscriptions create $SUBSCRIPTION_ID \
    --topic $TOPIC_ID \
    --push-endpoint=$WORKER_URL \
    --push-auth-service-account=$SERVICE_ACCOUNT \
    --ack-deadline=300 \
    --quiet 2>/dev/null || \
gcloud pubsub subscriptions update $SUBSCRIPTION_ID \
    --push-endpoint=$WORKER_URL \
    --push-auth-service-account=$SERVICE_ACCOUNT \
    --quiet

cd ..

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo "API URL: $API_URL"
echo ""
echo "Test with:"
echo "  curl -X POST \"$API_URL/ingest\" \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -d '{\"tenant_id\": \"acme\", \"log_id\": \"test-1\", \"text\": \"Hello World\"}'"
echo ""
echo "Check Firestore at:"
echo "  https://console.cloud.google.com/firestore/data?project=$PROJECT_ID"

