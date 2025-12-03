#!/bin/bash
# =============================================================================
# Test Script for the Ingestion API
# =============================================================================
# 
# Usage:
#   chmod +x test_api.sh
#   ./test_api.sh https://your-api-url.run.app
# =============================================================================

if [ -z "$1" ]; then
    echo "Usage: ./test_api.sh <api-url>"
    echo "Example: ./test_api.sh https://ingest-api-xxxxx-uc.a.run.app"
    exit 1
fi

API_URL=$1

echo "=== Testing API at: $API_URL ==="
echo ""

# Test 1: Health check
echo "Test 1: Health Check"
echo "-------------------"
curl -s "$API_URL/health" | python -m json.tool 2>/dev/null || curl -s "$API_URL/health"
echo ""
echo ""

# Test 2: JSON payload
echo "Test 2: JSON Payload (tenant: acme_corp)"
echo "----------------------------------------"
curl -s -X POST "$API_URL/ingest" \
    -H "Content-Type: application/json" \
    -d '{"tenant_id": "acme_corp", "log_id": "json-test-001", "text": "User 555-0199 logged in from IP 192.168.1.1"}' \
    | python -m json.tool 2>/dev/null || \
curl -s -X POST "$API_URL/ingest" \
    -H "Content-Type: application/json" \
    -d '{"tenant_id": "acme_corp", "log_id": "json-test-001", "text": "User 555-0199 logged in from IP 192.168.1.1"}'
echo ""
echo ""

# Test 3: Plain text payload
echo "Test 3: Plain Text Payload (tenant: beta_inc)"
echo "---------------------------------------------"
curl -s -X POST "$API_URL/ingest" \
    -H "Content-Type: text/plain" \
    -H "X-Tenant-ID: beta_inc" \
    -d "ERROR: Server crash at 10:30 AM. Call 555-123-4567 for support." \
    | python -m json.tool 2>/dev/null || \
curl -s -X POST "$API_URL/ingest" \
    -H "Content-Type: text/plain" \
    -H "X-Tenant-ID: beta_inc" \
    -d "ERROR: Server crash at 10:30 AM. Call 555-123-4567 for support."
echo ""
echo ""

# Test 4: Missing tenant_id (should fail)
echo "Test 4: Missing tenant_id (Expected: 400 Error)"
echo "-----------------------------------------------"
curl -s -X POST "$API_URL/ingest" \
    -H "Content-Type: application/json" \
    -d '{"text": "Some text without tenant"}' \
    | python -m json.tool 2>/dev/null || \
curl -s -X POST "$API_URL/ingest" \
    -H "Content-Type: application/json" \
    -d '{"text": "Some text without tenant"}'
echo ""
echo ""

# Test 5: Missing X-Tenant-ID header for text (should fail)
echo "Test 5: Missing X-Tenant-ID header (Expected: 400 Error)"
echo "--------------------------------------------------------"
curl -s -X POST "$API_URL/ingest" \
    -H "Content-Type: text/plain" \
    -d "Text without tenant header" \
    | python -m json.tool 2>/dev/null || \
curl -s -X POST "$API_URL/ingest" \
    -H "Content-Type: text/plain" \
    -d "Text without tenant header"
echo ""
echo ""

echo "=== Tests Complete ==="
echo ""
echo "Next steps:"
echo "1. Wait 30-60 seconds for processing"
echo "2. Check Firestore for documents in:"
echo "   - tenants/acme_corp/processed_logs/json-test-001"
echo "   - tenants/beta_inc/processed_logs/<generated-id>"

