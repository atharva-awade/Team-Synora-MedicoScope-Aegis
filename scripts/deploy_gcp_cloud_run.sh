#!/usr/bin/env bash
# ==============================================================================
# MedicoScope - Google Cloud Run Always-Free Deployment Script (Bash)
# Region: asia-south1 (Mumbai) | Cost: $0.00/month (Always Free Tier)
# ==============================================================================

set -euo pipefail

REGION="asia-south1"
PROJECT_ID="${1:-$(gcloud config get-value project 2>/dev/null || true)}"

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
    echo "[ERROR] No active GCP project found. Run 'gcloud init' or pass project ID: ./deploy_gcp_cloud_run.sh <PROJECT_ID>"
    exit 1
fi

echo "=========================================================="
echo " MedicoScope Google Cloud Run Deployment"
echo " Project: $PROJECT_ID | Region: $REGION"
echo "=========================================================="

echo "--> Enabling Cloud Run and Cloud Build APIs..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project "$PROJECT_ID"

echo "--> [1/2] Deploying Node.js Backend API..."
gcloud run deploy medicoscope-backend \
    --source server \
    --region "$REGION" \
    --platform managed \
    --allow-unauthenticated \
    --min-instances 0 \
    --max-instances 2 \
    --memory 512Mi \
    --cpu 1 \
    --project "$PROJECT_ID"

BACKEND_URL=$(gcloud run services describe medicoscope-backend --region "$REGION" --format 'value(status.url)' --project "$PROJECT_ID")
echo "[SUCCESS] Backend URL: $BACKEND_URL"

echo "--> [2/2] Deploying Gemini Chatbot Engine..."
gcloud run deploy medicoscope-chatbot \
    --source chatbot \
    --region "$REGION" \
    --platform managed \
    --allow-unauthenticated \
    --min-instances 0 \
    --max-instances 2 \
    --memory 512Mi \
    --cpu 1 \
    --set-env-vars "BACKEND_URL=${BACKEND_URL}/api" \
    --project "$PROJECT_ID"

CHATBOT_URL=$(gcloud run services describe medicoscope-chatbot --region "$REGION" --format 'value(status.url)' --project "$PROJECT_ID")
echo "[SUCCESS] Chatbot URL: $CHATBOT_URL"

echo "=========================================================="
echo " Deployment Complete!"
echo " Backend: $BACKEND_URL"
echo " Chatbot: $CHATBOT_URL"
echo "=========================================================="
