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

FQDN="$RECORD_NAME.$ZONE"
BASE_API="$API_URL/Services/REST/v1"

echo "Managing DNS record: $FQDN ($RECORD_TYPE)"

# Function to make API calls
api_call() {
    local method="$1"
    local endpoint="$2"
    local auth="$3"
    local data="$4"
    
    local response_file=$(mktemp)
    local http_code
    
    if [ -n "$data" ]; then
        http_code=$(curl -s -X "$method" \
            -H "Authorization: $auth" \
            -H "Content-Type: application/json" \
            -d "$data" \
            -w "%{http_code}" \
            -o "$response_file" \
            "$BASE_API/$endpoint")
    else
        http_code=$(curl -s -X "$method" \
            -H "Authorization: $auth" \
            -H "Content-Type: application/json" \
            -w "%{http_code}" \
            -o "$response_file" \
            "$BASE_API/$endpoint")
    fi
    
    local body=$(cat "$response_file")
    
    echo "$http_code|$body"
    rm -f "$response_file"
}

# Authentication
echo "Authenticating..."
auth_header="Basic $(echo -n "$USERNAME:$PASSWORD" | base64)"
auth_response=$(api_call "GET" "login" "$auth_header")

auth_code="${auth_response%%|*}"
auth_body="${auth_response#*|}"

if [ "$auth_code" != "200" ]; then
    echo "Authentication failed: $auth_code"
    echo "$auth_body"
    exit 1
fi

# Extract token
token=$(echo "$auth_body" | grep -o '"token": "[^"]*"' | cut -d'"' -f4)
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
existing_response=$(api_call "GET" "getHostRecordsByHint?hint=$FQDN" "$bam_auth")
existing_code="${existing_response%%|*}"
existing_body="${existing_response#*|}"

record_exists=false
record_id=""

if [ "$existing_code" = "200" ] && [ "$existing_body" != "[]" ]; then
    record_exists=true
    record_id=$(echo "$existing_body" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    echo "Existing record ID: $record_id"
fi

# Prepare record data
if [ "$RECORD_TYPE" = "TXT" ]; then
    record_data="{\"name\":\"$RECORD_NAME\",\"type\":\"$RECORD_TYPE\",\"rdata\":\"\\\"$RECORD_VALUE\\\"\",\"ttl\":$TTL,\"parentId\":$zone_id}"
else
    record_data="{\"name\":\"$RECORD_NAME\",\"type\":\"$RECORD_TYPE\",\"rdata\":\"$RECORD_VALUE\",\"ttl\":$TTL,\"parentId\":$zone_id}"
fi

if [ "$record_exists" = true ]; then
    # Update
    echo "Updating record..."
    if [ "$RECORD_TYPE" = "TXT" ]; then
        update_data="{\"id\":$record_id,\"name\":\"$RECORD_NAME\",\"type\":\"$RECORD_TYPE\",\"rdata\":\"\\\"$RECORD_VALUE\\\"\",\"ttl\":$TTL,\"parentId\":$zone_id}"
    else
        update_data="{\"id\":$record_id,\"name\":\"$RECORD_NAME\",\"type\":\"$RECORD_TYPE\",\"rdata\":\"$RECORD_VALUE\",\"ttl\":$TTL,\"parentId\":$zone_id}"
    fi
    
    update_response=$(api_call "PUT" "update" "$bam_auth" "$update_data")
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
    create_response=$(api_call "POST" "addHostRecord" "$bam_auth" "$record_data")
    create_code="${create_response%%|*}"
    create_body="${create_response#*|}"
    
    if [ "$create_code" -ge 200 ] && [ "$create_code" -lt 300 ]; then
        echo "Created successfully"
        new_id=$(echo "$create_body" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
        if [ -z "$new_id" ]; then
            new_id="$create_body"
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
