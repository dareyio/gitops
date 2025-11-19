#!/bin/bash
# Script to inject test errors for Application Errors dashboard testing
# This will generate 4xx and potentially 5xx errors to populate the dashboard

set -e

echo "🔴 Injecting test errors for dashboard testing..."
echo ""

# Get the API endpoint
API_URL="${DAREYSCORE_API_URL:-http://dareyscore-api.dareyscore.svc:8000}"

# Function to make a request and show result
make_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    local description=$4
    
    echo "📡 $description"
    if [ -n "$data" ]; then
        curl -s -w "\n   Status: %{http_code}\n" -X "$method" "$API_URL$endpoint" \
            -H "Content-Type: application/json" \
            -d "$data" || true
    else
        curl -s -w "\n   Status: %{http_code}\n" -X "$method" "$API_URL$endpoint" || true
    fi
    echo ""
}

# Generate 4xx errors (Client Errors)
echo "=== Generating 4xx Errors ==="

# 1. 404 - Non-existent endpoint
for i in {1..10}; do
    make_request "GET" "/api/v1/nonexistent-endpoint-$i" "" "404 Error: Non-existent endpoint"
    sleep 0.5
done

# 2. 400 - Invalid request body
for i in {1..5}; do
    make_request "POST" "/api/v1/events" "invalid json" "400 Error: Invalid JSON"
    sleep 0.5
done

# 3. 400 - Missing required fields
make_request "POST" "/api/v1/events" '{"event_type":"test"}' "400 Error: Missing required fields"
sleep 0.5

# 4. 401 - Unauthorized (if auth is required)
make_request "GET" "/api/v1/scores" "" "401/403 Error: Unauthorized"
sleep 0.5

# 5. 405 - Method not allowed
make_request "DELETE" "/api/v1/health" "" "405 Error: Method not allowed"
sleep 0.5

# 6. 422 - Unprocessable entity (invalid data)
make_request "POST" "/api/v1/events" '{"event_type":"","payload":{}}' "422 Error: Invalid data"
sleep 0.5

# Generate 5xx errors (if possible, safely)
echo "=== Attempting to generate 5xx errors (safely) ==="

# Try to trigger server errors with malformed but valid JSON
for i in {1..3}; do
    make_request "POST" "/api/v1/events" '{"event_type":"assessment_completed","payload":{"proficiency_level":999,"score_percentage":-1}}' "500 Error: Invalid values"
    sleep 0.5
done

# Try very large payload (might cause 413 or 500)
make_request "POST" "/api/v1/events" "{\"event_type\":\"test\",\"payload\":{\"data\":\"$(python3 -c 'print("x" * 10000)')\"}}" "413/500 Error: Large payload"
sleep 0.5

echo "✅ Error injection complete!"
echo ""
echo "📊 Check the Application Errors dashboard in Grafana:"
echo "   - Select namespace: dareyscore"
echo "   - Look for 4xx and 5xx errors"
echo "   - Data should appear within 30-60 seconds"
echo ""
echo "💡 To generate more errors, run this script again:"
echo "   ./inject-test-errors.sh"

