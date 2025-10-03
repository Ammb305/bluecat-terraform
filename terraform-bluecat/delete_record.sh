#!/bin/bash
# BlueCat DNS Record Deletion Script - REST API v2

set -e

# Parse arguments
API_URL="$1"
USERNAME="$2"
PASSWORD="$3"
ZONE="$4"
RECORD_TYPE="$5"
RECORD_NAME="$6"
MODULE_PATH="$7"
API_VERSION="$8"
API_PATH="$9"

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

# Extract token
token=$(echo "$auth_response" | grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

if [ -z "$token" ]; then
    token=$(echo "$auth_response" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

if [ -z "$token" ]; then
    token=$(echo "$auth_response" | jq -r '.token' 2>/dev/null || echo "")
fi

if [ -z "$token" ] || [ "$token" = "null" ]; then
    echo "Auth failed. Could not extract token from response: $auth_response"
    exit 1
fi

echo "Token extracted successfully: ${token:0:8}..."
auth_header="Authorization: Bearer $token"

# --- Get Zone ---
echo "Getting zone ID for: $ZONE"
zone_response=$(curl -s -X GET "$BASE_API_URL/zones?name=$ZONE" -H "$auth_header")

zone_id=$(echo "$zone_response" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/' | head -1)

if [ -z "$zone_id" ]; then
    zone_id=$(echo "$zone_response" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
fi

if [ -z "$zone_id" ]; then
    zone_id=$(echo "$zone_response" | jq -r '.[0].id' 2>/dev/null || echo "")
fi

if [ -z "$zone_id" ] || [ "$zone_id" = "null" ]; then
    echo "Zone not found: $ZONE"
    echo "Response: $zone_response"
    exit 1
fi

echo "Zone ID: $zone_id"

# --- Find record to delete ---
echo "Finding record to delete..."
record_response=$(curl -s -X GET "$BASE_API_URL/records?zone=$zone_id&name=$FQDN&type=$RECORD_TYPE" -H "$auth_header")

record_id=$(echo "$record_response" | grep -o '"id":[0-9]*' | head -1 | sed 's/"id"://')

if [ -z "$record_id" ]; then
    echo "Record not found: $FQDN ($RECORD_TYPE)"
    echo "This may be expected if the record was already deleted."
    curl -s -X DELETE "$BASE_API_URL/sessions/$token" -H "$auth_header" > /dev/null 2>&1
    exit 0
fi

echo "Found record ID: $record_id"

# --- Delete record ---
echo "Deleting record..."
delete_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X DELETE "$BASE_API_URL/records/$record_id" \
    -H "$auth_header")

if [ "$delete_code" = "204" ] || [ "$delete_code" = "200" ]; then
    echo "Record deleted successfully"
else
    echo "Delete failed with code: $delete_code"
    curl -s -X DELETE "$BASE_API_URL/sessions/$token" -H "$auth_header" > /dev/null 2>&1
    exit 1
fi

# --- Logout ---
curl -s -X DELETE "$BASE_API_URL/sessions/$token" -H "$auth_header" > /dev/null 2>&1
echo "Deletion completed successfully"