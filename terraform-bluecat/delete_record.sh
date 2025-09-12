#!/bin/bash
# BlueCat DNS Record Deletion Script

set -e

MODULE_PATH="$1"
API_URL="$2"
ZONE="$3"
API_VERSION="${4:-v1}"
API_PATH="${5}"

# Check if files exist
if [ ! -f "$MODULE_PATH/.terraform_token" ] || [ ! -f "$MODULE_PATH/.terraform_record_id" ]; then
    echo "No token or record ID found, skipping deletion"
    exit 0
fi

# Read values
token=$(cat "$MODULE_PATH/.terraform_token")
record_id=$(cat "$MODULE_PATH/.terraform_record_id")

# Determine the correct API base path
if [ -n "$API_PATH" ]; then
    # Use custom API path (e.g., "/api/v2")
    BASE_API="$API_URL$API_PATH"
else
    # Use standard BlueCat path with version
    BASE_API="$API_URL/Services/REST/$API_VERSION"
fi
echo "Deleting record ID: $record_id"

# Function to make API calls  
api_call() {
    local method="$1"
    local endpoint="$2"
    local auth="$3"
    local data="$4"
    
    local http_code_flag="-w %{http_code}"
    local response_file=$(mktemp)
    
    if [ -n "$data" ]; then
        curl -s -X "$method" \
            -H "Authorization: $auth" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$http_code_flag" \
            "$BASE_API/$endpoint" > "$response_file"
    else
        curl -s -X "$method" \
            -H "Authorization: $auth" \
            -H "Content-Type: application/json" \
            "$http_code_flag" \
            "$BASE_API/$endpoint" > "$response_file"
    fi
    
    local content=$(cat "$response_file")
    local http_code="${content: -3}"
    local body="${content%???}"
    
    echo "$http_code|$body"
    rm -f "$response_file"
}

bam_auth="BAMAuthToken: $token"

# Get zone for deployment
zone_response=$(api_call "GET" "getZonesByHint?hint=$ZONE" "$bam_auth")
zone_code=$(echo "$zone_response" | cut -d'|' -f1)
zone_body=$(echo "$zone_response" | cut -d'|' -f2-)

if [ "$zone_code" = "200" ]; then
    zone_id=$(echo "$zone_body" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    
    # Delete record
    delete_response=$(api_call "DELETE" "delete?objectId=$record_id" "$bam_auth")
    delete_code=$(echo "$delete_response" | cut -d'|' -f1)
    
    if [ "$delete_code" -ge 200 ] && [ "$delete_code" -lt 300 ]; then
        echo "Deleted successfully"
        
        # Deploy
        if [ -n "$zone_id" ]; then
            deploy_data="{\"entityId\":$zone_id}"
            api_call "POST" "quickDeploy" "$bam_auth" "$deploy_data" > /dev/null
        fi
    else
        echo "Delete failed: $delete_code"
    fi
fi

# Logout and cleanup
api_call "GET" "logout" "$bam_auth" > /dev/null

rm -f "$MODULE_PATH/.terraform_token"
rm -f "$MODULE_PATH/.terraform_record_id" 
rm -f "$MODULE_PATH/.terraform_operation_status"

echo "Cleanup completed"
