#!/bin/bash
# BlueCat DNS Record Deletion Script - REST API v2
# Version 4: JSON input compatible with external data source pattern

set -e

# Read JSON input from stdin (same pattern as manage_record.sh)
input=$(cat)

# Function to extract JSON values (same as manage_record.sh)
extract_json() {
    local json="$1"
    local key="$2"
    echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed "s/\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\"/\1/"
}

# Extract values from JSON input
API_URL=$(extract_json "$input" "api_url")
USERNAME=$(extract_json "$input" "username")
PASSWORD=$(extract_json "$input" "password")
ZONE=$(extract_json "$input" "zone")
VIEW=$(extract_json "$input" "view")
RECORD_TYPE=$(extract_json "$input" "record_type")
RECORD_NAME=$(extract_json "$input" "record_name")
RECORD_ID=$(extract_json "$input" "record_id")
API_PATH=$(extract_json "$input" "api_path")
AUTO_DEPLOY=$(extract_json "$input" "auto_deploy")

# Debug: Show what we extracted
echo "DEBUG: Delete operation - Extracted values:" >&2
echo "  API_URL: $API_URL" >&2
echo "  USERNAME: $USERNAME" >&2
echo "  ZONE: $ZONE" >&2
echo "  VIEW: $VIEW" >&2
echo "  RECORD_NAME: $RECORD_NAME" >&2
echo "  RECORD_TYPE: $RECORD_TYPE" >&2
echo "  RECORD_ID: $RECORD_ID" >&2
echo "  AUTO_DEPLOY: $AUTO_DEPLOY" >&2
echo "" >&2

# Validate required fields
if [ -z "$API_URL" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$ZONE" ]; then
    echo "ERROR: Missing required fields for deletion" >&2
    echo "Input received: $input" >&2
    exit 1
fi

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

# Extract token (no jq needed)
token=$(echo "$auth_response" | grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

if [ -z "$token" ]; then
    token=$(echo "$auth_response" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

if [ -z "$token" ] || [ "$token" = "null" ]; then
    echo "Auth failed. Could not extract token from response: $auth_response"
    exit 1
fi

echo "Token extracted successfully: ${token:0:8}..."
auth_header="Authorization: Bearer $token"

# --- Get Zone ---
echo "Getting zone ID for: $ZONE"
if [ -n "$VIEW" ]; then
    echo "Using view filter: $VIEW"
    zone_response=$(curl -s -X GET "$BASE_API_URL/zones?name=$ZONE&view=$VIEW" -H "$auth_header")
else
    echo "No view filter specified"
    zone_response=$(curl -s -X GET "$BASE_API_URL/zones?name=$ZONE" -H "$auth_header")
fi

zone_id=$(echo "$zone_response" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/' | head -1)

if [ -z "$zone_id" ]; then
    zone_id=$(echo "$zone_response" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
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
echo "Deleting record..." >&2
delete_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X DELETE "$BASE_API_URL/records/$record_id" \
    -H "$auth_header")

if [ "$delete_code" = "204" ] || [ "$delete_code" = "200" ]; then
    echo "Record deleted successfully" >&2
    operation_status="deleted"
else
    echo "Delete failed with code: $delete_code" >&2
    curl -s -X DELETE "$BASE_API_URL/sessions/$token" -H "$auth_header" > /dev/null 2>&1 >&2
    exit 1
fi

# --- Deploy changes if auto_deploy is enabled ---
deployment_status="not_deployed"
deployed_servers=""

if [ "$AUTO_DEPLOY" = "true" ] || [ "$AUTO_DEPLOY" = "1" ]; then
    echo "============================================" >&2
    echo "Deploying changes to DNS servers..." >&2
    echo "============================================" >&2
    
    # Get deployment roles for the zone
    echo "Auto-discovering DNS servers for zone..." >&2
    roles_response=$(curl -s -X GET "$BASE_API_URL/zones/$zone_id/deploymentRoles" -H "$auth_header")
    
    echo "DeploymentRoles response: $roles_response" >&2
    
    # Extract server IDs from deployment roles
    server_ids=$(echo "$roles_response" | grep -o '"server"[[:space:]]*:[[:space:]]*{[^}]*"id"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*' | head -10)
    
    # If deployment roles didn't work, try getting all DNS servers
    if [ -z "$server_ids" ]; then
        echo "Trying alternative: Get all DNS servers..." >&2
        servers_response=$(curl -s -X GET "$BASE_API_URL/servers?type=DNS" -H "$auth_header")
        echo "Servers response (first 500 chars): $(echo "$servers_response" | head -c 500)" >&2
        
        server_ids=$(echo "$servers_response" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*' | head -10)
    fi
    
    if [ -n "$server_ids" ]; then
        echo "Found servers to deploy to: $server_ids" >&2
        
        deployed_list=""
        for server_id in $server_ids; do
            echo "Attempting deployment to server ID: $server_id" >&2
            
            deploy_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
                -X POST "$BASE_API_URL/servers/$server_id/services/DNS/deploy" \
                -H "$auth_header" \
                -H "Content-Type: application/json" \
                -d '{}')
            
            http_code=$(echo "$deploy_response" | grep -o "HTTPSTATUS:[0-9]*" | grep -o "[0-9]*")
            response_body=$(echo "$deploy_response" | sed 's/HTTPSTATUS:[0-9]*$//')
            
            echo "  HTTP Code: $http_code" >&2
            echo "  Response: $(echo "$response_body" | head -c 200)" >&2
            
            if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
                echo "  ✓ Successfully deployed to server $server_id" >&2
                if [ -z "$deployed_list" ]; then
                    deployed_list="$server_id"
                else
                    deployed_list="$deployed_list,$server_id"
                fi
            else
                echo "  ✗ Deployment failed to server $server_id" >&2
            fi
        done
        
        if [ -n "$deployed_list" ]; then
            deployment_status="deployed"
            deployed_servers="$deployed_list"
            echo "============================================" >&2
            echo "Deployment completed: $deployment_status" >&2
            echo "Deployed to servers: $deployed_servers" >&2
        else
            deployment_status="failed"
            echo "============================================" >&2
            echo "Deployment failed: No servers deployed successfully" >&2
        fi
    else
        deployment_status="no_servers"
        echo "============================================" >&2
        echo "Deployment skipped: No DNS servers found for zone" >&2
    fi
    echo "============================================" >&2
fi

# --- Logout ---
curl -s -X DELETE "$BASE_API_URL/sessions/$token" -H "$auth_header" > /dev/null 2>&1
echo "Session closed" >&2

# Output JSON result for Terraform (to stdout)
echo "{\"record_id\":\"$record_id\",\"operation_status\":\"$operation_status\",\"fqdn\":\"$FQDN\",\"zone_id\":\"$zone_id\",\"deployment_status\":\"$deployment_status\",\"deployed_servers\":\"$deployed_servers\"}"