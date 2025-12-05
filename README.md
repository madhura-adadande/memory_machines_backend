# Robust Data Processor - Backend Engineering Assessment

A scalable, multi-tenant data ingestion pipeline built on Google Cloud Platform.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           UNIFIED INGESTION GATEWAY                              │
└─────────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────┐         ┌──────────────┐
    │   JSON       │         │   TXT        │
    │   Payload    │         │   Payload    │
    │              │         │              │
    │ Content-Type:│         │ Content-Type:│
    │ application/ │         │ text/plain   │
    │ json         │         │ X-Tenant-ID  │
    └──────┬───────┘         └──────┬───────┘
           │                        │
           └──────────┬─────────────┘
                      │
                      ▼
    ┌─────────────────────────────────────┐
    │         POST /ingest                │
    │         (Cloud Run - API)           │
    │                                     │
    │  • Validates input                  │
    │  • Normalizes to internal format    │
    │  • Returns 202 Accepted instantly   │
    └─────────────────┬───────────────────┘
                      │
                      ▼
    ┌─────────────────────────────────────┐
    │         Google Pub/Sub              │
    │         (Message Broker)            │
    │                                     │
    │  • Decouples API from Worker        │
    │  • Enables async processing         │
    │  • Auto-retries on failure          │
    └─────────────────┬───────────────────┘
                      │
                      ▼
    ┌─────────────────────────────────────┐
    │         Worker Service              │
    │         (Cloud Run - Worker)        │
    │                                     │
    │  • Simulates heavy processing       │
    │  • 0.05s sleep per character        │
    │  • Redacts sensitive data           │
    └─────────────────┬───────────────────┘
                      │
                      ▼
    ┌─────────────────────────────────────┐
    │         Google Firestore            │
    │         (NoSQL Database)            │
    │                                     │
    │  tenants/                           │
    │    └── {tenant_id}/                 │
    │          └── processed_logs/        │
    │                └── {log_id}         │
    └─────────────────────────────────────┘
```

## 🔑 Key Design Decisions

### 1. Multi-Tenant Isolation
Data is strictly isolated using Firestore sub-collections:
```
tenants/{tenant_id}/processed_logs/{log_id}
```
- `acme_corp` data is in `tenants/acme_corp/processed_logs/`
- `beta_inc` data is in `tenants/beta_inc/processed_logs/`
- No cross-tenant data access possible

### 2. Crash Recovery (Chaos Handling)
- **Pub/Sub Acknowledgment**: If the worker crashes or returns non-2xx, Pub/Sub automatically retries
- **At-least-once delivery**: Messages are not lost if processing fails
- **Idempotent writes**: Using `log_id` as document ID ensures no duplicates

### 3. High Throughput (1000+ RPM)
- **Non-blocking API**: Returns `202 Accepted` immediately
- **Cloud Run autoscaling**: Scales up to handle load
- **Pub/Sub buffering**: Absorbs traffic spikes

## 📁 Project Structure

```
.
├── api/
│   ├── main.py           # API service code
│   ├── requirements.txt  # Python dependencies
│   └── Dockerfile        # Container config
├── worker/
│   ├── main.py           # Worker service code
│   ├── requirements.txt  # Python dependencies
│   └── Dockerfile        # Container config
├── deploy.sh             # Deployment script
└── README.md             # This file
```

## 🚀 Deployment Guide

### Prerequisites
1. Google Cloud account (free tier works)
2. Google Cloud SDK installed
3. Docker installed (for local testing)

### Step-by-Step Deployment

#### 1. Create GCP Project
```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Create project (or use existing)
gcloud projects create $PROJECT_ID

# Set as active project
gcloud config set project $PROJECT_ID

# Enable billing (required even for free tier)
# Do this in the Cloud Console: https://console.cloud.google.com/billing
```

#### 2. Enable Required APIs
```bash
gcloud services enable \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    pubsub.googleapis.com \
    firestore.googleapis.com
```

#### 3. Create Firestore Database
```bash
# Create Firestore in Native mode
gcloud firestore databases create --location=us-central1
```

#### 4. Create Pub/Sub Topic and Subscription
```bash
# Create the topic
gcloud pubsub topics create ingest-topic

# We'll create the subscription after deploying the worker
```

#### 5. Deploy API Service
```bash
# Navigate to api directory
cd api

# Deploy to Cloud Run
gcloud run deploy ingest-api \
    --source . \
    --platform managed \
    --region us-central1 \
    --allow-unauthenticated \
    --set-env-vars "GCP_PROJECT_ID=$PROJECT_ID,PUBSUB_TOPIC_ID=ingest-topic"

# Note the URL output (e.g., https://ingest-api-xxxxx-uc.a.run.app)
export API_URL="<your-api-url>"
```

#### 6. Deploy Worker Service
```bash
# Navigate to worker directory
cd ../worker

# Deploy to Cloud Run
gcloud run deploy ingest-worker \
    --source . \
    --platform managed \
    --region us-central1 \
    --no-allow-unauthenticated \
    --set-env-vars "GCP_PROJECT_ID=$PROJECT_ID"

# Note the URL output
export WORKER_URL="<your-worker-url>"
```

#### 7. Create Pub/Sub Push Subscription
```bash
# Get the Cloud Run service account
export SERVICE_ACCOUNT=$(gcloud run services describe ingest-worker \
    --region us-central1 \
    --format="value(spec.template.spec.serviceAccountName)")

# Create push subscription to worker
gcloud pubsub subscriptions create ingest-subscription \
    --topic ingest-topic \
    --push-endpoint=$WORKER_URL \
    --push-auth-service-account=$SERVICE_ACCOUNT \
    --ack-deadline=300
```

## 🧪 Testing

### Test JSON Payload
```bash
curl -X POST "$API_URL/ingest" \
    -H "Content-Type: application/json" \
    -d '{"tenant_id": "acme_corp", "log_id": "test-123", "text": "User 555-0199 logged in"}'
```

Expected response:
```json
{
    "status": "accepted",
    "message_id": "12345678",
    "log_id": "test-123",
    "tenant_id": "acme_corp"
}
```

### Test Plain Text Payload
```bash
curl -X POST "$API_URL/ingest" \
    -H "Content-Type: text/plain" \
    -H "X-Tenant-ID: beta_inc" \
    -d "Server error at 10:30 AM. Contact 555-123-4567 for support."
```

### Verify in Firestore
1. Go to [Firestore Console](https://console.cloud.google.com/firestore)
2. Navigate to: `tenants > acme_corp > processed_logs > test-123`
3. Verify the document exists with `modified_data` field (phone redacted)

## 📊 Example Firestore Document

```json
{
    "source": "json_upload",
    "original_text": "User 555-0199 logged in",
    "modified_data": "User [REDACTED] logged in",
    "processed_at": "2024-12-03T10:00:00Z",
    "received_at": "2024-12-03T09:59:58Z",
    "text_length": 23
}
```

## 🔄 How Crash Recovery Works

1. **API receives request** → Publishes to Pub/Sub → Returns `202`
2. **Pub/Sub delivers to Worker** → Worker starts processing
3. **If Worker crashes** → Pub/Sub doesn't receive acknowledgment
4. **Pub/Sub retries** → Message redelivered after ack deadline
5. **Worker recovers** → Processes message successfully
6. **Worker returns `200`** → Pub/Sub marks message as acknowledged

This ensures **no data loss** even if the worker crashes mid-processing.

## 💰 Cost Considerations (Free Tier)

| Service | Free Tier Limit | This Project Usage |
|---------|-----------------|-------------------|
| Cloud Run | 2M requests/month | Well under |
| Pub/Sub | 10GB/month | Well under |
| Firestore | 1GB storage, 50K reads/day | Well under |

## 🛠️ Local Development

### Run API Locally
```bash
cd api
pip install -r requirements.txt
export GCP_PROJECT_ID="your-project-id"
export PUBSUB_TOPIC_ID="ingest-topic"
python main.py
```

### Run Worker Locally
```bash
cd worker
pip install -r requirements.txt
python main.py
```

