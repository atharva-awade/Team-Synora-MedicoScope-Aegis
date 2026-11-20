# ==============================================================================
# MedicoScope - Google Cloud Run Always-Free Deployment Script (PowerShell)
# Region: asia-south1 (Mumbai) | Cost: $0.00/month (Always Free Tier)
# ==============================================================================

param(
    [string]$ProjectId = "",
    [string]$Region = "asia-south1",
    [string]$GeminiApiKey = "",
    [string]$GroqApiKey = ""
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

# 3. Resolve API Keys (from args, env, or chatbot/.env)
if (-not $GeminiApiKey -and $env:GEMINI_API_KEY) {
    $GeminiApiKey = $env:GEMINI_API_KEY
}
if (-not $GroqApiKey -and $env:GROQ_API_KEY) {
    $GroqApiKey = $env:GROQ_API_KEY
}
if (Test-Path "chatbot/.env") {
    $envContent = Get-Content "chatbot/.env"
    if (-not $GeminiApiKey) {
        $gLine = $envContent | Where-Object { $_ -match "^GEMINI_API_KEY=(.*)$" }
        if ($gLine) { $GeminiApiKey = ($gLine -replace "^GEMINI_API_KEY=", "").Trim().Trim('"') }
    }
    if (-not $GroqApiKey) {
        $qLine = $envContent | Where-Object { $_ -match "^GROQ_API_KEY=(.*)$" }
        if ($qLine) { $GroqApiKey = ($qLine -replace "^GROQ_API_KEY=", "").Trim().Trim('"') }
    }
}

Write-Host "Using Project ID: $ProjectId" -ForegroundColor Yellow
Write-Host "Deploying to Region: $Region (Mumbai, India)" -ForegroundColor Yellow
if ($GeminiApiKey) {
    Write-Host "Gemini API: Configured (Secured via Cloud Run Environment)" -ForegroundColor Green
} else {
    Write-Host "[WARNING] GEMINI_API_KEY not found. Pass -GeminiApiKey <KEY>" -ForegroundColor Yellow
}

# 4. Enable Required GCP APIs ($0 cost)
Write-Host "`n--> Enabling Cloud Run and Cloud Build APIs..." -ForegroundColor Cyan
& gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project $ProjectId

Write-Host "`n--> Configuring IAM permissions for Cloud Build..." -ForegroundColor Cyan
$projectNumber = (& gcloud projects describe $ProjectId --format='value(projectNumber)').Trim()
& gcloud projects add-iam-policy-binding $ProjectId --member="serviceAccount:${projectNumber}-compute@developer.gserviceaccount.com" --role="roles/storage.admin" --condition=None --quiet
& gcloud projects add-iam-policy-binding $ProjectId --member="serviceAccount:${projectNumber}-compute@developer.gserviceaccount.com" --role="roles/artifactregistry.writer" --condition=None --quiet
& gcloud projects add-iam-policy-binding $ProjectId --member="serviceAccount:${projectNumber}@cloudbuild.gserviceaccount.com" --role="roles/storage.admin" --condition=None --quiet

# 5. Deploy Node.js Backend API
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

# Build environment variables list
$envVars = "BACKEND_URL=$BACKEND_URL/api"
if ($GeminiApiKey) {
    $envVars += ",GEMINI_API_KEY=$GeminiApiKey"
}
if ($GroqApiKey) {
    $envVars += ",GROQ_API_KEY=$GroqApiKey"
}

# 6. Deploy Python FastChat / Gemini Chatbot
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
    --set-env-vars "$envVars" `
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
