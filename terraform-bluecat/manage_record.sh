#!/bin/bash
# BlueCat DNS Record Management Script - REST API v2
# Version 3: No jq dependency

set -e

# Read JSON input from stdin (for external data source)
input=$(cat)

# Extract values from JSON input without jq - using grep and sed
API_URL=$(echo "$input" | grep -o '"api_url":"[^"]*"' | sed 's/"api_url":"\(.*\)"/\1/')
USERNAME=$(echo "$input" | grep -o '"username":"[^"]*"' | sed 's/"username":"\(.*\)"/\1/')
PASSWORD=$(echo "$input" | grep -o '"password":"[^"]*"' | sed 's/"password":"\(.*\)"/\1/')
ZONE=$(echo "$input" | grep -o '"zone":"[^"]*"' | sed 's/"zone":"\(.*\)"/\1/')
RECORD_TYPE=$(echo "$input" | grep -o '"record_type":"[^"]*"' | sed 's/"record_type":"\(.*\)"/\1/')
RECORD_NAME=$(echo "$input" | grep -o '"record_name":"[^"]*"' | sed 's/"record_name":"\(.*\)"/\1/')
RECORD_VALUE=$(echo "$input" | grep -o '"record_value":"[^"]*"' | sed 's/"record_value":"\(.*\)"/\1/')
TTL=$(echo "$input" | grep -o '"ttl":"[^"]*"' | sed 's/"ttl":"\(.*\)"/\1/')
API_VERSION=$(echo "$input" | grep -o '"api_version":"[^"]*"' | sed 's/"api_version":"\(.*\)"/\1/')
API_PATH=$(echo "$input" | grep -o '"api_path":"[^"]*"' | sed 's/"api_path":"\(.*\)"/\1/')

# Construct the full API base URL
if [ -n "$API_PATH" ]; then
    BASE_API_URL="$API_URL$API_PATH"
else
    BASE_API_URL="$API_URL/api/v2"
fi

FQDN="$RECORD_NAME.$ZONE"

# Output debug info to stderr (won't interfere with JSON output)
echo "Managing DNS record: $FQDN ($RECORD_TYPE) using API v2" >&2
echo "Base API URL: $BASE_API_URL" >&2

# --- Authentication ---
echo "Authenticating..." >&2
auth_response=$(curl -s -X POST "$BASE_API_URL/sessions" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")

# Extract token from JSON response (no jq needed)
token=$(echo "$auth_response" | grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

if [ -z "$token" ]; then
    token=$(echo "$auth_response" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

if [ -z "$token" ] || [ "$token" = "null" ]; then
    echo "Auth failed. Could not extract token from response: $auth_response" >&2
    exit 1
fi

echo "Token extracted successfully: ${token:0:8}..." >&2

auth_header="Authorization: Bearer $token"

# --- Get Zone ---
echo "Getting zone ID for: $ZONE" >&2
zone_response=$(curl -s -X GET "$BASE_API_URL/zones?name=$ZONE" -H "$auth_header")

zone_id=$(echo "$zone_response" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/' | head -1)

if [ -z "$zone_id" ]; then
    zone_id=$(echo "$zone_response" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
fi

if [ -z "$zone_id" ] || [ "$zone_id" = "null" ]; then
    echo "Zone not found: $ZONE" >&2
    echo "Response: $zone_response" >&2
    exit 1
fi

echo "Zone ID: $zone_id" >&2

# --- Check existing record ---
echo "Checking for existing record..." >&2
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
    echo "Unsupported record type: $RECORD_TYPE" >&2
    exit 1
fi

# --- Update or Create ---
operation_status=""
final_record_id=""

if [ -n "$record_id" ]; then
    echo "Updating record ID: $record_id" >&2
    
    response_file=$(mktemp)
    update_code=$(curl -s -o "$response_file" -w "%{http_code}" \
        -X PUT "$BASE_API_URL/records/$record_id" \
        -H "$auth_header" -H "Content-Type: application/json" \
        -d "$record_json")
    
    update_body=$(cat "$response_file")
    rm -f "$response_file"

    if [ "$update_code" = "200" ]; then
        echo "Record updated successfully" >&2
        operation_status="updated"
        final_record_id="$record_id"
    else
        echo "Update failed. Code: $update_code" >&2
        echo "Response: $update_body" >&2
        exit 1
    fi
else
    echo "Creating new record..." >&2
    
    response_file=$(mktemp)
    create_code=$(curl -s -o "$response_file" -w "%{http_code}" \
        -X POST "$BASE_API_URL/records" \
        -H "$auth_header" -H "Content-Type: application/json" \
        -d "$record_json")
    
    create_body=$(cat "$response_file")
    rm -f "$response_file"

    if [ "$create_code" = "201" ]; then
        new_id=$(echo "$create_body" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/' | head -1)
        
        if [ -z "$new_id" ]; then
            new_id=$(echo "$create_body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
        fi
        
        echo "Record created with ID: $new_id" >&2
        operation_status="created"
        final_record_id="$new_id"
    else
        echo "Create failed. Code: $create_code" >&2
        echo "Response: $create_body" >&2
        exit 1
    fi
fi

# --- Logout ---
curl -s -X DELETE "$BASE_API_URL/sessions/$token" -H "$auth_header" > /dev/null 2>&1
echo "Completed successfully" >&2

# Output JSON result to stdout for Terraform to capture (no jq needed)
# This is the ONLY output to stdout - everything else goes to stderr
printf '{"record_id":"%s","operation_status":"%s","fqdn":"%s","zone_id":"%s"}\n' \
    "$final_record_id" "$operation_status" "$FQDN" "$zone_id"