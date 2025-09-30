#!/bin/bash
# BlueCat DNS Record Deletion Script

set -e

# Parse command line arguments
API_URL="$1"
USERNAME="$2"
PASSWORD="$3"
ZONE="$4"
RECORD_TYPE="$5"
RECORD_NAME="$6"
MODULE_PATH="$7"
API_VERSION="${8:-v1}"
API_PATH="${9}"

FQDN="$RECORD_NAME.$ZONE"

# Determine the correct API base path
if [ -n "$API_PATH" ]; then
    # Use custom API path (e.g., "/api/v2")
    BASE_API="$API_URL$API_PATH"
else
    # Use standard BlueCat path with version
    BASE_API="$API_URL/Services/REST/$API_VERSION"
fi

echo "Deleting DNS record: $FQDN ($RECORD_TYPE)"

# Function to make API calls
api_call() {
    local method="$1"
    local endpoint="$2"
    local auth="$3"
    local data="$4"
    
    local response_file=$(mktemp)
    local header_file=$(mktemp)
    
    local curl_opts=(-s -X "$method" \
        -H "Authorization: $auth" \
        -H "Content-Type: application/json" \
        -o "$response_file" \
        -D "$header_file")

    if [ -n "$data" ]; then
        curl_opts+=(-d "$data")
    fi
    
    # The -w flag must be the LAST option before the URL.
    # It writes the status code to stdout after the request is complete.
    local http_code=$(curl "${curl_opts[@]}" -w "%{http_code}" "$BASE_API/$endpoint")
    
    local body=$(cat "$response_file")
    local headers=$(cat "$header_file")
    
    echo "$http_code|$headers|$body"
    rm -f "$response_file" "$header_file"
}

# Authentication
echo "Authenticating..."
auth_header="Basic $(echo -n "$USERNAME:$PASSWORD" | base64)"

# Determine login endpoint based on API path
if [[ "$BASE_API" == *"/api/v2"* ]]; then
    # Use sessions endpoint for v2 API with /api/v2 path
    login_endpoint="sessions"
else
    # Use standard login endpoint
    login_endpoint="login"
fi

auth_response=$(api_call "POST" "$login_endpoint" "$auth_header" "{}")

auth_code="${auth_response%%|*}"
auth_headers_and_body="${auth_response#*|}"
auth_headers="${auth_headers_and_body%%|*}"
auth_body="${auth_headers_and_body#*|}"

if [ "$auth_code" != "200" ] && [ "$auth_code" != "201" ]; then
    echo "Authentication failed: $auth_code"
    echo "$auth_body"
    exit 1
fi

# Extract token
token=""
if [[ "$BASE_API" == *"/api/v2"* ]]; then
    # For v2, extract from header
    token_line=$(echo "$auth_headers" | grep -i "Authorization")
    token=$(echo "$token_line" | sed -n 's/Authorization: BAMAuthToken: \(.*\)/\1/p' | tr -d '[:space:]')
else
    # For v1, extract from body
    token=$(echo "$auth_body" | grep -o '"token": "[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$token" ]; then
    echo "Failed to extract token"
    exit 1
fi

bam_auth="BAMAuthToken: $token"

# Get zone information
echo "Getting zone: $ZONE"
zone_response=$(api_call "GET" "getZonesByHint?hint=$ZONE" "$bam_auth")

zone_code="${zone_response%%|*}"
zone_body="${zone_response#*|}"

if [ "$zone_code" != "200" ]; then
    echo "Failed to get zone: $zone_code"
    exit 1
fi

zone_id=$(echo "$zone_body" | grep -o '"id": [0-9]*' | head -1 | sed 's/"id": //')
if [ -z "$zone_id" ]; then
    echo "Zone not found: $ZONE"
    exit 1
fi

echo "Zone ID: $zone_id"

# Get record ID
echo "Getting zone entities to find record for deletion..."
entities_response=$(api_call "GET" "zones/${zone_id}/entities?start=0&count=1000" "$bam_auth")
entities_code="${entities_response%%|*}"
entities_body="${entities_response#*|}"

if [ "$entities_code" != "200" ]; then
    echo "Failed to get zone entities: $entities_code"
    exit 1
fi

# Parse JSON response to find matching record (without jq dependency)
record_found=false
record_id=""

# Check if the response contains data array and look for matching records
if echo "$entities_body" | grep -q '"data"'; then
    # Look for records with matching name and type
    # Split response by records and check each one
    while IFS= read -r line; do
        if echo "$line" | grep -q "\"name\": \"$RECORD_NAME\"" && echo "$line" | grep -q "\"type\": \"$RECORD_TYPE\""; then
            record_id=$(echo "$line" | grep -o '"id":[0-9]*' | sed 's/"id"://')
            if [ -n "$record_id" ]; then
                record_found=true
                break
            fi
        fi
    done <<< "$(echo "$entities_body" | grep -o '{[^}]*}' | grep '"id"')"
fi

# Debug output
echo "Looking for record: name='$RECORD_NAME', type='$RECORD_TYPE'"
echo "Record found: $record_found"
if [ "$record_found" = true ]; then
    echo "Record ID for deletion: $record_id"
fi

if [ "$record_found" = false ]; then
    echo "Record not found, skipping deletion."
    exit 0
fi
echo "Found record ID for deletion: $record_id"

# Delete record
delete_response=$(api_call "DELETE" "entities/$record_id" "$bam_auth")
delete_code="${delete_response%%|*}"

if [ "$delete_code" -ge 200 ] && [ "$delete_code" -lt 300 ]; then
    echo "Deleted successfully"
else
    echo "Delete failed: $delete_code"
    # Even if delete fails, we proceed to deploy and logout
fi

# Deploy
echo "Deploying deletion..."
deploy_data="{\"entityId\":$zone_id}"
deploy_response=$(api_call "POST" "quickDeploy" "$bam_auth" "$deploy_data")
deploy_code="${deploy_response%%|*}"

if [ "$deploy_code" -ge 200 ] && [ "$deploy_code" -lt 300 ]; then
    echo "Deployed successfully"
else
    echo "Deploy warning: $deploy_code"
fi

# Logout
api_call "GET" "logout" "$bam_auth" > /dev/null

# Clean up local state files
rm -f "$MODULE_PATH/.terraform_token"
rm -f "$MODULE_PATH/.terraform_record_id"
rm -f "$MODULE_PATH/.terraform_operation_status"

echo "Cleanup completed"
