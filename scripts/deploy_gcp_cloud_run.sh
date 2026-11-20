#!/usr/bin/env bash
# ==============================================================================
# MedicoScope - Google Cloud Run Always-Free Deployment Script (Bash)
# Region: asia-south1 (Mumbai) | Cost: $0.00/month (Always Free Tier)
# ==============================================================================

set -euo pipefail

REGION="asia-south1"
PROJECT_ID="${1:-$(gcloud config get-value project 2>/dev/null || true)}"
GEMINI_KEY="${2:-${GEMINI_API_KEY:-}}"
GROQ_KEY="${3:-${GROQ_API_KEY:-}}"

# Auto-extract from chatbot/.env if present and not provided as an argument
if [ -z "$GEMINI_KEY" ] && [ -f chatbot/.env ]; then
    GEMINI_KEY=$(grep -E '^GEMINI_API_KEY=' chatbot/.env | cut -d '=' -f2- | tr -d '\r"' || true)
fi
if [ -z "$GROQ_KEY" ] && [ -f chatbot/.env ]; then
    GROQ_KEY=$(grep -E '^GROQ_API_KEY=' chatbot/.env | cut -d '=' -f2- | tr -d '\r"' || true)
fi

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
    echo "[ERROR] No active GCP project found. Run 'gcloud init' or pass project ID: ./deploy_gcp_cloud_run.sh <PROJECT_ID> [GEMINI_API_KEY]"
    exit 1
fi

echo "=========================================================="
echo " MedicoScope Google Cloud Run Deployment"
echo " Project: $PROJECT_ID | Region: $REGION"
if [ -n "$GEMINI_KEY" ]; then
    echo " Gemini API: Configured (Secured via Cloud Run Environment)"
else
    echo " [WARNING] GEMINI_API_KEY not found. Pass it as second argument: ./deploy_gcp_cloud_run.sh <PROJECT_ID> <GEMINI_API_KEY>"
fi
echo "=========================================================="

echo "--> Enabling Cloud Run and Cloud Build APIs..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project "$PROJECT_ID"

echo "--> Granting Cloud Build permissions to default service accounts..."
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/storage.admin" \
    --condition=None --quiet || true

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/artifactregistry.writer" \
    --condition=None --quiet || true

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/storage.admin" \
    --condition=None --quiet || true

echo "--> [1/2] Deploying Node.js Backend API..."
gcloud run deploy medicoscope-backend \
    --source server \
    --region "$REGION" \
    --platform managed \
    --allow-unauthenticated \
    --port 8080 \
    --min-instances 0 \
    --max-instances 2 \
    --memory 512Mi \
    --cpu 1 \
    --set-env-vars "NODE_ENV=production" \
    --project "$PROJECT_ID"

BACKEND_URL=$(gcloud run services describe medicoscope-backend --region "$REGION" --format 'value(status.url)' --project "$PROJECT_ID")
echo "[SUCCESS] Backend URL: $BACKEND_URL"

ENV_VARS="BACKEND_URL=${BACKEND_URL}/api"
if [ -n "$GEMINI_KEY" ]; then
    ENV_VARS="${ENV_VARS},GEMINI_API_KEY=${GEMINI_KEY}"
fi
if [ -n "$GROQ_KEY" ]; then
    ENV_VARS="${ENV_VARS},GROQ_API_KEY=${GROQ_KEY}"
fi

echo "--> [2/2] Deploying Gemini Chatbot Engine..."
gcloud run deploy medicoscope-chatbot \
    --source chatbot \
    --region "$REGION" \
    --platform managed \
    --allow-unauthenticated \
    --port 8080 \
    --min-instances 0 \
    --max-instances 2 \
    --memory 512Mi \
    --cpu 1 \
    --set-env-vars "$ENV_VARS" \
    --project "$PROJECT_ID"

CHATBOT_URL=$(gcloud run services describe medicoscope-chatbot --region "$REGION" --format 'value(status.url)' --project "$PROJECT_ID")
echo "[SUCCESS] Chatbot URL: $CHATBOT_URL"

echo "=========================================================="
echo " Deployment Complete!"
echo " Backend: $BACKEND_URL"
echo " Chatbot: $CHATBOT_URL"
echo "=========================================================="
