# =============================================================================
# Test Script for the Ingestion API (PowerShell for Windows)
# =============================================================================
# 
# Usage:
#   .\test_api.ps1 -ApiUrl "https://your-api-url.run.app"
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$ApiUrl
)

Write-Host "=== Testing API at: $ApiUrl ===" -ForegroundColor Green
Write-Host ""

# Test 1: Health check
Write-Host "Test 1: Health Check" -ForegroundColor Yellow
Write-Host "-------------------"
try {
    $response = Invoke-RestMethod -Uri "$ApiUrl/health" -Method Get
    $response | ConvertTo-Json
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
}
Write-Host ""

# Test 2: JSON payload
Write-Host "Test 2: JSON Payload (tenant: acme_corp)" -ForegroundColor Yellow
Write-Host "----------------------------------------"
$jsonBody = @{
    tenant_id = "acme_corp"
    log_id = "json-test-001"
    text = "User 555-0199 logged in from IP 192.168.1.1"
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$ApiUrl/ingest" -Method Post -Body $jsonBody -ContentType "application/json"
    $response | ConvertTo-Json
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
}
Write-Host ""

# Test 3: Plain text payload
Write-Host "Test 3: Plain Text Payload (tenant: beta_inc)" -ForegroundColor Yellow
Write-Host "---------------------------------------------"
$headers = @{
    "Content-Type" = "text/plain"
    "X-Tenant-ID" = "beta_inc"
}
$textBody = "ERROR: Server crash at 10:30 AM. Call 555-123-4567 for support."

try {
    $response = Invoke-RestMethod -Uri "$ApiUrl/ingest" -Method Post -Body $textBody -Headers $headers
    $response | ConvertTo-Json
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
}
Write-Host ""

# Test 4: Missing tenant_id (should fail)
Write-Host "Test 4: Missing tenant_id (Expected: 400 Error)" -ForegroundColor Yellow
Write-Host "-----------------------------------------------"
$badJsonBody = @{
    text = "Some text without tenant"
} | ConvertTo-Json

try {
    $response = Invoke-WebRequest -Uri "$ApiUrl/ingest" -Method Post -Body $badJsonBody -ContentType "application/json"
    Write-Host "Status: $($response.StatusCode)"
    $response.Content
} catch {
    Write-Host "Expected Error: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Green
}
Write-Host ""

# Test 5: Missing X-Tenant-ID header for text (should fail)
Write-Host "Test 5: Missing X-Tenant-ID header (Expected: 400 Error)" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------"
try {
    $response = Invoke-WebRequest -Uri "$ApiUrl/ingest" -Method Post -Body "Text without tenant header" -ContentType "text/plain"
    Write-Host "Status: $($response.StatusCode)"
    $response.Content
} catch {
    Write-Host "Expected Error: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Green
}
Write-Host ""

Write-Host "=== Tests Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Wait 30-60 seconds for processing"
Write-Host "2. Check Firestore for documents in:"
Write-Host "   - tenants/acme_corp/processed_logs/json-test-001"
Write-Host "   - tenants/beta_inc/processed_logs/<generated-id>"

