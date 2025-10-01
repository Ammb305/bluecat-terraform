#!/bin/bash
# BlueCat DNS Record Deletion Script - REST API v2

set -e

# Parse arguments
API_URL="$1"        # e.g. http://localhost:5001
USERNAME="$2"
PASSWORD="$3"
ZONE="$4"
RECORD_TYPE="$5"    # A, CNAME, TXT
RECORD_NAME="$6"    # e.g. www
MODULE_PATH="$7"
API_VERSION="$8"     # e.g. v2
API_PATH="$9"        # e.g. /api/v2

# Construct the full API base URL
if [ -n "$API_PATH" ]; then
    BASE_API_URL="$API_URL$API_PATH"
else
    BASE_API_URL="$API_URL/api/v2"
fi

FQDN="$RECORD_NAME.$ZONE"

echo "Deleting DNS record: $FQDN ($RECORD_TYPE) using API v2"
echo "Base API URL: $BASE_API_URL"

# --- Authentication ---
echo "Authenticating..."
auth_response=$(curl -s -X POST "$BASE_API_URL/sessions" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")

# Extract token from JSON response with multiple methods
token=$(echo "$auth_response" | grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

if [ -z "$token" ]; then
    # Try alternate extraction method
    token=$(echo "$auth_response" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

if [ -z "$token" ]; then
    # Try jq if available (silent fallback)
    token=$(echo "$auth_response" | jq -r '.token' 2>/dev/null || echo "")
fi

if [ -z "$token" ] || [ "$token" = "null" ]; then
    echo "Auth failed. Could not extract token from response: $auth_response"
    exit 1
fi

echo "Token extracted successfully: ${token:0:8}..."

auth_header="Authorization: Bearer $token"
echo "$token" > "$MODULE_PATH/.terraform_token"

# --- Get Zone ---
echo "Getting zone ID for: $ZONE"
zone_response=$(curl -s -X GET "$BASE_API_URL/zones?name=$ZONE" -H "$auth_header")

# Extract zone ID from JSON response with multiple methods
zone_id=$(echo "$zone_response" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/' | head -1)

if [ -z "$zone_id" ]; then
    # Try alternate extraction method
    zone_id=$(echo "$zone_response" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
fi

if [ -z "$zone_id" ]; then
    # Try jq if available (silent fallback)
    zone_id=$(echo "$zone_response" | jq -r '.[0].id' 2>/dev/null || echo "")
fi

if [ -z "$zone_id" ] || [ "$zone_id" = "null" ]; then
    echo "Zone not found: $ZONE"
    echo "Response: $zone_response"
    exit 1
fi
echo "Zone ID: $zone_id"

# --- Find the record ---
echo "Looking for record to delete..."
record_response=$(curl -s -X GET "$BASE_API_URL/records?zone=$zone_id&name=$FQDN&type=$RECORD_TYPE" -H "$auth_header")

# Extract record ID with improved pattern (handles whitespace)
record_id=$(echo "$record_response" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/' | head -1)

if [ -z "$record_id" ]; then
    # Try alternate extraction method
    record_id=$(echo "$record_response" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
fi

if [ -z "$record_id" ]; then
    # Try jq if available
    record_id=$(echo "$record_response" | jq -r '.[0].id' 2>/dev/null || echo "")
fi

if [ -z "$record_id" ] || [ "$record_id" = "null" ]; then
    echo "Record not found, nothing to delete."
    echo "Response: $record_response"
    exit 0
fi
echo "Found record ID: $record_id"

# --- Delete record ---
echo "Deleting record..."

# Store response body and code separately
response_file=$(mktemp)
delete_code=$(curl -s -o "$response_file" -w "%{http_code}" -X DELETE "$BASE_API_URL/records/$record_id" -H "$auth_header")
delete_body=$(cat "$response_file")
rm -f "$response_file"

if [ "$delete_code" -ge 200 ] && [ "$delete_code" -lt 300 ]; then
    echo "Record deleted successfully"
else
    echo "Delete failed: $delete_code"
    echo "Response: $delete_body"
fi

# --- Deploy zone changes ---
echo "Deploying deletion..."

# Store response body and code separately
response_file=$(mktemp)
deploy_code=$(curl -s -o "$response_file" -w "%{http_code}" -X POST "$BASE_API_URL/zones/$zone_id/deploy" -H "$auth_header")
deploy_body=$(cat "$response_file")
rm -f "$response_file"

if [ "$deploy_code" -ge 200 ] && [ "$deploy_code" -lt 300 ]; then
    echo "Zone deployed successfully"
else
    echo "Deploy warning: $deploy_code"
    echo "Response: $deploy_body"
fi

# --- Logout ---
curl -s -X DELETE "$BASE_API_URL/sessions/$token" -H "$auth_header" > /dev/null

# --- Cleanup local state files ---
rm -f "$MODULE_PATH/.terraform_token"
rm -f "$MODULE_PATH/.terraform_record_id"
rm -f "$MODULE_PATH/.terraform_operation_status"

echo "Deletion completed successfully"
