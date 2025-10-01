#!/bin/bash
# BlueCat DNS Record Management Script - REST API v2

set -e

# Parse arguments
API_URL="$1"        # e.g. http://localhost:5001
USERNAME="$2"
PASSWORD="$3"
ZONE="$4"
RECORD_TYPE="$5"    # A, CNAME, TXT
RECORD_NAME="$6"    # e.g. www
RECORD_VALUE="$7"   # e.g. 1.2.3.4 or target cname
TTL="$8"
MODULE_PATH="$9"
API_VERSION="${10}"  # e.g. v2
API_PATH="${11}"     # e.g. /api/v2

# Construct the full API base URL
if [ -n "$API_PATH" ]; then
    BASE_API_URL="$API_URL$API_PATH"
else
    BASE_API_URL="$API_URL/api/v2"
fi

FQDN="$RECORD_NAME.$ZONE"

echo "Managing DNS record: $FQDN ($RECORD_TYPE) using API v2"
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

# --- Check existing record ---
echo "Checking for existing record..."
record_response=$(curl -s -X GET "$BASE_API_URL/records?zone=$zone_id&name=$FQDN&type=$RECORD_TYPE" -H "$auth_header")

record_id=$(echo "$record_response" | grep -o '"id":[0-9]*' | head -1 | sed 's/"id"://')

# --- Build JSON payload ---
if [ "$RECORD_TYPE" = "A" ] || [ "$RECORD_TYPE" = "AAAA" ]; then
    record_json="{\"name\":\"$FQDN\",\"type\":\"$RECORD_TYPE\",\"rdata\":{\"address\":\"$RECORD_VALUE\"},\"ttl\":$TTL,\"zoneId\":$zone_id}"
elif [ "$RECORD_TYPE" = "CNAME" ]; then
    record_json="{\"name\":\"$FQDN\",\"type\":\"CNAME\",\"rdata\":{\"cname\":\"$RECORD_VALUE\"},\"ttl\":$TTL,\"zoneId\":$zone_id}"
elif [ "$RECORD_TYPE" = "TXT" ]; then
    record_json="{\"name\":\"$FQDN\",\"type\":\"TXT\",\"rdata\":{\"text\":\"$RECORD_VALUE\"},\"ttl\":$TTL,\"zoneId\":$zone_id}"
else
    echo "Unsupported record type: $RECORD_TYPE"
    exit 1
fi

# --- Update or Create ---
if [ -n "$record_id" ]; then
    echo "Updating record ID: $record_id"
    
    # Store response body and code separately
    response_file=$(mktemp)
    update_code=$(curl -s -o "$response_file" -w "%{http_code}" \
        -X PUT "$BASE_API_URL/records/$record_id" \
        -H "$auth_header" -H "Content-Type: application/json" \
        -d "$record_json")
    
    update_body=$(cat "$response_file")
    rm -f "$response_file"

    if [ "$update_code" = "200" ]; then
        echo "Record updated successfully"
        echo "$record_id" > "$MODULE_PATH/.terraform_record_id"
        echo "updated" > "$MODULE_PATH/.terraform_operation_status"
    else
        echo "Update failed. Code: $update_code"
        echo "Response: $update_body"
        exit 1
    fi
else
    echo "Creating new record..."
    
    # Store response body and code separately to avoid parsing issues
    response_file=$(mktemp)
    create_code=$(curl -s -o "$response_file" -w "%{http_code}" \
        -X POST "$BASE_API_URL/records" \
        -H "$auth_header" -H "Content-Type: application/json" \
        -d "$record_json")
    
    create_body=$(cat "$response_file")
    rm -f "$response_file"

    if [ "$create_code" = "201" ]; then
        # Extract ID with improved pattern (handles whitespace)
        new_id=$(echo "$create_body" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/' | head -1)
        
        # Fallback extraction methods
        if [ -z "$new_id" ]; then
            new_id=$(echo "$create_body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
        fi
        
        if [ -z "$new_id" ]; then
            new_id=$(echo "$create_body" | jq -r '.id' 2>/dev/null || echo "")
        fi
        
        echo "Record created with ID: $new_id"
        echo "$new_id" > "$MODULE_PATH/.terraform_record_id"
        echo "created" > "$MODULE_PATH/.terraform_operation_status"
    else
        echo "Create failed. Code: $create_code"
        echo "Response: $create_body"
        exit 1
    fi
fi

# --- Logout ---
curl -s -X DELETE "$BASE_API_URL/sessions/$token" -H "$auth_header" > /dev/null
echo "Completed successfully"
