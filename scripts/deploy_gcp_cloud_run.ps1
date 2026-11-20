# ==============================================================================
# MedicoScope - Google Cloud Run Always-Free Deployment Script (PowerShell)
# Region: asia-south1 (Mumbai) | Cost: $0.00/month (Always Free Tier)
# ==============================================================================

param(
    [string]$ProjectId = "",
    [string]$Region = "asia-south1"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " MedicoScope Google Cloud Run Automated Deployment" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check gcloud CLI
try {
    $gcloudVersion = & gcloud --version 2>&1
    Write-Host "[OK] gcloud CLI detected." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Google Cloud SDK (gcloud) is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Please download from: https://cloud.google.com/sdk/docs/install" -ForegroundColor Yellow
    exit 1
}

# 2. Resolve Active Project
if (-not $ProjectId) {
    $ProjectId = (& gcloud config get-value project 2>&1).Trim()
}

if (-not $ProjectId -or $ProjectId -eq "(unset)") {
    Write-Host "[ERROR] No active GCP project found. Run:" -ForegroundColor Red
    Write-Host "  gcloud init" -ForegroundColor Yellow
    Write-Host "  or pass -ProjectId <your-project-id>" -ForegroundColor Yellow
    exit 1
}

Write-Host "Using Project ID: $ProjectId" -ForegroundColor Yellow
Write-Host "Deploying to Region: $Region (Mumbai, India)" -ForegroundColor Yellow

# 3. Enable Required GCP APIs ($0 cost)
Write-Host "`n--> Enabling Cloud Run and Cloud Build APIs..." -ForegroundColor Cyan
& gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project $ProjectId

# 4. Deploy Node.js Backend API
Write-Host "`n--> [1/2] Deploying MedicoScope Node.js API to Cloud Run..." -ForegroundColor Cyan
& gcloud run deploy medicoscope-backend `
    --source server `
    --region $Region `
    --platform managed `
    --allow-unauthenticated `
    --min-instances 0 `
    --max-instances 2 `
    --memory 512Mi `
    --cpu 1 `
    --project $ProjectId

$BACKEND_URL = (& gcloud run services describe medicoscope-backend --region $Region --format 'value(status.url)' --project $ProjectId).Trim()
Write-Host "[SUCCESS] Node.js Backend URL: $BACKEND_URL" -ForegroundColor Green

# 5. Deploy Python FastChat / Gemini Chatbot
Write-Host "`n--> [2/2] Deploying MedicoScope Gemini Chatbot Engine to Cloud Run..." -ForegroundColor Cyan
& gcloud run deploy medicoscope-chatbot `
    --source chatbot `
    --region $Region `
    --platform managed `
    --allow-unauthenticated `
    --min-instances 0 `
    --max-instances 2 `
    --memory 512Mi `
    --cpu 1 `
    --set-env-vars "BACKEND_URL=$BACKEND_URL/api" `
    --project $ProjectId

$CHATBOT_URL = (& gcloud run services describe medicoscope-chatbot --region $Region --format 'value(status.url)' --project $ProjectId).Trim()
Write-Host "[SUCCESS] Gemini Chatbot URL: $CHATBOT_URL" -ForegroundColor Green

# 6. Summary & Flutter Instructions
Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " Deployment Complete! (Scale-to-Zero = $0/mo cost)" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Node Backend:    $BACKEND_URL" -ForegroundColor White
Write-Host "Gemini Chatbot:  $CHATBOT_URL" -ForegroundColor White
Write-Host "`nUpdate lib/core/constants/api_constants.dart with these URLs:" -ForegroundColor Yellow
Write-Host "  static const String baseUrl = '$BACKEND_URL/api';" -ForegroundColor White
Write-Host "  static const String chatbotBaseUrl = '$CHATBOT_URL';" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Green
