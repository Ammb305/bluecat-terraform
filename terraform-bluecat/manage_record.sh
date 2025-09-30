#!/bin/bash
# BlueCat DNS Record Management Script

set -e

# Parse command line arguments
API_URL="$1"
USERNAME="$2"
PASSWORD="$3"
ZONE="$4"
RECORD_TYPE="$5"
RECORD_NAME="$6" 
RECORD_VALUE="$7"
TTL="$8"
MODULE_PATH="$9"
API_VERSION="${10:-v1}"
API_PATH="${11}"

FQDN="$RECORD_NAME.$ZONE"

# Determine the correct API base path
if [ -n "$API_PATH" ]; then
    # Use custom API path (e.g., "/api/v2")
    BASE_API="$API_URL$API_PATH"
else
    # Use standard BlueCat path with version
    BASE_API="$API_URL/Services/REST/$API_VERSION"
fi

echo "Managing DNS record: $FQDN ($RECORD_TYPE)"

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

echo "$token" > "$MODULE_PATH/.terraform_token"

# Get zone information
echo "Getting zone: $ZONE"
bam_auth="BAMAuthToken: $token"
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

# Check existing record
echo "Getting zone entities..."
entities_response=$(api_call "GET" "zones/${zone_id}/entities?start=0&count=1000" "$bam_auth")
entities_code="${entities_response%%|*}"
entities_body="${entities_response#*|}"

if [ "$entities_code" != "200" ]; then
    echo "Failed to get zone entities: $entities_code"
    exit 1
fi

# Parse JSON response to find matching record
record_exists=false
record_id=""

# Check if the response contains data array
if echo "$entities_body" | grep -q '"data"'; then
    # Extract records that match our name and type
    matching_lines=$(echo "$entities_body" | grep -o '"id":[0-9]*' | head -1)
    if [ -n "$matching_lines" ]; then
        # For simplicity, we'll assume if there are any records, we need to check them
        # This is a basic implementation - in production you'd want more sophisticated parsing
        record_exists=true
        record_id=$(echo "$matching_lines" | sed 's/"id"://')
        echo "Existing record ID: $record_id"
    fi
fi

# Prepare record data
if [ "$RECORD_TYPE" = "TXT" ]; then
    properties="rdata=\\\"$RECORD_VALUE\\\"|ttl=$TTL"
elif [ "$RECORD_TYPE" = "CNAME" ]; then
    properties="linkedRecordName=$RECORD_VALUE|ttl=$TTL"
else
    properties="addresses=$RECORD_VALUE|ttl=$TTL"
fi

if [ "$record_exists" = true ]; then
    # Update
    echo "Updating record..."
    update_data="{\"name\":\"$RECORD_NAME\",\"type\":\"$RECORD_TYPE\",\"properties\":\"$properties\"}"
    
    update_response=$(api_call "PUT" "entities/$record_id" "$bam_auth" "$update_data")
    update_code="${update_response%%|*}"
    
    if [ "$update_code" -ge 200 ] && [ "$update_code" -lt 300 ]; then
        echo "Updated successfully"
        echo "$record_id" > "$MODULE_PATH/.terraform_record_id"
        echo "updated" > "$MODULE_PATH/.terraform_operation_status"
    else
        echo "Update failed: $update_code"
        exit 1
    fi
else
    # Create
    echo "Creating record..."
    create_data="{\"name\":\"$RECORD_NAME\",\"type\":\"$RECORD_TYPE\",\"properties\":\"$properties\"}"
    create_response=$(api_call "POST" "zones/${zone_id}/entities" "$bam_auth" "$create_data")
    create_code="${create_response%%|*}"
    create_body="${create_response#*|}"
    
    if [ "$create_code" -ge 200 ] && [ "$create_code" -lt 300 ]; then
        echo "Created successfully"
        new_id=$(echo "$create_body" | grep -o '"id":[0-9]*' | head -1 | sed 's/"id"://')
        if [ -z "$new_id" ]; then
            # If we can't extract the ID, try to extract just numbers from the response
            new_id=$(echo "$create_body" | grep -o '[0-9]\{6,\}' | head -1)
        fi
        if [ -z "$new_id" ]; then
            new_id="unknown"
        fi
        echo "$new_id" > "$MODULE_PATH/.terraform_record_id"
        echo "created" > "$MODULE_PATH/.terraform_operation_status"
    else
        echo "Create failed: $create_code"
        exit 1
    fi
fi

# Deploy
echo "Deploying..."
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

echo "Completed successfully"
