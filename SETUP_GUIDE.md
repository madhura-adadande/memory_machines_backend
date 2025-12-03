# 🚀 Complete GCP Setup Guide (For Beginners)

This guide walks you through everything from creating a Google Cloud account to deploying the application.

## Part 1: Setting Up Google Cloud (One-Time Setup)

### Step 1: Create a Google Cloud Account

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Sign in with your Google account (or create one)
3. You'll get **$300 free credits** for 90 days (new users)

### Step 2: Create a New Project

1. Click the project dropdown at the top of the page
2. Click "New Project"
3. Enter a project name (e.g., `data-processor-assessment`)
4. Note your **Project ID** (you'll need this later)
5. Click "Create"

### Step 3: Enable Billing

Even for free tier, billing must be enabled:

1. Go to [Billing](https://console.cloud.google.com/billing)
2. Click "Link a billing account"
3. Add a payment method (you won't be charged if you stay within free tier)

### Step 4: Install Google Cloud SDK

**Windows (PowerShell as Administrator):**
```powershell
# Download and run installer
(New-Object Net.WebClient).DownloadFile("https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe", "$env:Temp\GoogleCloudSDKInstaller.exe")
& $env:Temp\GoogleCloudSDKInstaller.exe
```

Or download from: https://cloud.google.com/sdk/docs/install

**Mac:**
```bash
brew install google-cloud-sdk
```

**Linux:**
```bash
curl https://sdk.cloud.google.com | bash
```

### Step 5: Initialize Google Cloud SDK

```bash
# Login to your Google account
gcloud auth login

# Set your project
gcloud config set project YOUR_PROJECT_ID
```

---

## Part 2: Manual Deployment (Step-by-Step)

If you prefer to deploy manually instead of using the script:

### Step 1: Enable Required APIs

```bash
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable pubsub.googleapis.com
gcloud services enable firestore.googleapis.com
```

### Step 2: Create Firestore Database

**Option A: Using CLI**
```bash
gcloud firestore databases create --location=us-central1
```

**Option B: Using Console**
1. Go to [Firestore Console](https://console.cloud.google.com/firestore)
2. Click "Create Database"
3. Select "Native mode" (not Datastore mode)
4. Choose location: `us-central1`
5. Click "Create"

### Step 3: Create Pub/Sub Topic

**Option A: Using CLI**
```bash
gcloud pubsub topics create ingest-topic
```

**Option B: Using Console**
1. Go to [Pub/Sub Console](https://console.cloud.google.com/cloudpubsub)
2. Click "Create Topic"
3. Topic ID: `ingest-topic`
4. Click "Create"

### Step 4: Deploy API Service

```bash
# Navigate to api folder
cd api

# Deploy (this builds and deploys automatically)
gcloud run deploy ingest-api \
    --source . \
    --platform managed \
    --region us-central1 \
    --allow-unauthenticated \
    --set-env-vars "GCP_PROJECT_ID=YOUR_PROJECT_ID,PUBSUB_TOPIC_ID=ingest-topic"
```

**Save the URL** that's displayed after deployment!

### Step 5: Deploy Worker Service

```bash
# Navigate to worker folder
cd ../worker

# Deploy
gcloud run deploy ingest-worker \
    --source . \
    --platform managed \
    --region us-central1 \
    --no-allow-unauthenticated \
    --set-env-vars "GCP_PROJECT_ID=YOUR_PROJECT_ID" \
    --timeout=300
```

**Save this URL too!**

### Step 6: Connect Pub/Sub to Worker

This is the trickiest part. We need to:
1. Give Pub/Sub permission to call our Worker
2. Create a subscription that pushes to the Worker

```bash
# Get your project number
PROJECT_NUMBER=$(gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)")

# The Pub/Sub service account
SERVICE_ACCOUNT="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"

# Grant permission to invoke the Worker
gcloud run services add-iam-policy-binding ingest-worker \
    --region us-central1 \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/run.invoker"

# Create the subscription (replace WORKER_URL with your actual URL)
gcloud pubsub subscriptions create ingest-subscription \
    --topic ingest-topic \
    --push-endpoint=YOUR_WORKER_URL \
    --push-auth-service-account=$SERVICE_ACCOUNT \
    --ack-deadline=300
```

---

## Part 3: Using the Deployment Script

If you have bash available (Git Bash on Windows, or Mac/Linux):

```bash
# Make script executable
chmod +x deploy.sh

# Run deployment
./deploy.sh YOUR_PROJECT_ID us-central1
```

---

## Part 4: Testing Your Deployment

### Test 1: JSON Payload

```bash
curl -X POST "YOUR_API_URL/ingest" \
    -H "Content-Type: application/json" \
    -d '{"tenant_id": "acme_corp", "log_id": "test-001", "text": "User 555-0199 accessed the system"}'
```

Expected Response:
```json
{
    "status": "accepted",
    "message_id": "1234567890",
    "log_id": "test-001",
    "tenant_id": "acme_corp"
}
```

### Test 2: Plain Text Payload

```bash
curl -X POST "YOUR_API_URL/ingest" \
    -H "Content-Type: text/plain" \
    -H "X-Tenant-ID: beta_inc" \
    -d "Error log: Contact support at 555-123-4567"
```

### Test 3: Verify in Firestore

1. Go to [Firestore Console](https://console.cloud.google.com/firestore)
2. You should see: `tenants` → `acme_corp` → `processed_logs` → `test-001`
3. The document should have:
   - `original_text`: The original input
   - `modified_data`: Phone numbers replaced with `[REDACTED]`
   - `processed_at`: Timestamp
   - `source`: `json_upload` or `text_upload`

---

## Part 5: Troubleshooting

### "Permission denied" errors
```bash
# Re-authenticate
gcloud auth login

# Ensure you have the right project
gcloud config set project YOUR_PROJECT_ID
```

### API returns errors
```bash
# Check API logs
gcloud run services logs read ingest-api --region us-central1 --limit 50
```

### Worker not processing
```bash
# Check Worker logs
gcloud run services logs read ingest-worker --region us-central1 --limit 50

# Check Pub/Sub subscription status
gcloud pubsub subscriptions describe ingest-subscription
```

### Firestore empty after testing
- Wait 30+ seconds (processing takes time based on text length)
- Check Worker logs for errors
- Verify Pub/Sub subscription is correctly pointing to Worker URL

---

## Part 6: Cleanup (After Assessment)

To avoid any charges, delete everything:

```bash
# Delete Cloud Run services
gcloud run services delete ingest-api --region us-central1 --quiet
gcloud run services delete ingest-worker --region us-central1 --quiet

# Delete Pub/Sub
gcloud pubsub subscriptions delete ingest-subscription --quiet
gcloud pubsub topics delete ingest-topic --quiet

# Delete Firestore (must be done in Console)
# Go to: https://console.cloud.google.com/firestore
# Settings → Delete database

# Or delete the entire project
gcloud projects delete YOUR_PROJECT_ID
```

---

## Quick Reference: Key URLs

| Service | Console URL |
|---------|-------------|
| Cloud Run | https://console.cloud.google.com/run |
| Pub/Sub | https://console.cloud.google.com/cloudpubsub |
| Firestore | https://console.cloud.google.com/firestore |
| Logs | https://console.cloud.google.com/logs |
| Billing | https://console.cloud.google.com/billing |

---

## Need Help?

- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Firestore Documentation](https://cloud.google.com/firestore/docs)

