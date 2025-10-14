#!/bin/bash
# BlueCat DNS Record Management Script - REST API v2
# Version 4: With Deployment Support

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

# Optional: DNS Server ID for deployment (if empty, will auto-discover)
DNS_SERVER_ID=$(echo "$input" | grep -o '"dns_server_id":"[^"]*"' | sed 's/"dns_server_id":"\(.*\)"/\1/' || echo "")

# Auto-deploy flag
AUTO_DEPLOY=$(echo "$input" | grep -o '"auto_deploy":"[^"]*"' | sed 's/"auto_deploy":"\(.*\)"/\1/' || echo "true")

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

# --- Deploy Changes ---
deployment_status="not_deployed"
deployed_servers=""

if [ "$AUTO_DEPLOY" = "true" ] || [ "$AUTO_DEPLOY" = "1" ]; then
    echo "============================================" >&2
    echo "Deploying changes to DNS servers..." >&2
    echo "============================================" >&2

if [ -n "$DNS_SERVER_ID" ]; then
    # Deploy to specific server if provided
    echo "Deploying to specified DNS server ID: $DNS_SERVER_ID using v2 API..." >&2
    
    deploy_url="$BASE_API_URL/deployments"
    echo "DEBUG: Deploying to URL: $deploy_url" >&2
    
    deploy_result=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -X POST "$deploy_url" \
        -H "$auth_header" \
        -H "Content-Type: application/json" \
        -d "{\"serverId\":$DNS_SERVER_ID,\"entityId\":$zone_id}")
    
    http_code=$(echo "$deploy_result" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
    deploy_body=$(echo "$deploy_result" | sed '/HTTP_CODE:/d')
    
    echo "Deployment HTTP Code: $http_code" >&2
    echo "Deployment Response: $deploy_body" >&2
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
        echo "✓ Successfully deployed to server $DNS_SERVER_ID" >&2
        deployment_status="deployed"
        deployed_servers="$DNS_SERVER_ID"
    else
        echo "✗ Deployment failed. HTTP Code: $http_code" >&2
        echo "Response: $deploy_body" >&2
    fi
else
    # Auto-discover deployment servers for this zone
    echo "Auto-discovering DNS servers for zone..." >&2
    
    # Try multiple API endpoints for getting deployment info
    roles_url="$BASE_API_URL/zones/$zone_id/deploymentRoles"
    echo "DEBUG: Getting deployment roles from URL: $roles_url" >&2
    
    deploy_response=$(curl -s -X GET "$roles_url" -H "$auth_header")
    echo "DeploymentRoles response: $deploy_response" >&2
    
    # Extract all server IDs - try multiple patterns
    server_ids=$(echo "$deploy_response" | grep -o '"serverId"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\([0-9]*\)/\1/')
    
    # Alternative: Try getting all servers and deploy to all
    if [ -z "$server_ids" ]; then
        echo "Trying alternative: Get all servers..." >&2
        servers_url="$BASE_API_URL/servers?type=DNS"
        echo "DEBUG: Getting DNS servers from URL: $servers_url" >&2
        
        servers_response=$(curl -s -X GET "$servers_url" -H "$auth_header")
        echo "Servers response: $servers_response" >&2
        server_ids=$(echo "$servers_response" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\([0-9]*\)/\1/')
    fi
    
    # Alternative: Try deployment options endpoint
    if [ -z "$server_ids" ]; then
        echo "Trying alternative: Get deployment options..." >&2
        options_response=$(curl -s -X GET "$BASE_API_URL/zones/$zone_id/deploymentOptions" -H "$auth_header")
        echo "Deployment options response: $options_response" >&2
        server_ids=$(echo "$options_response" | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\([0-9]*\)/\1/')
    fi
    
    if [ -z "$server_ids" ]; then
        echo "⚠ Warning: No deployment servers found for zone" >&2
        echo "API Response: $deploy_response" >&2
        echo "Record was created but NOT deployed" >&2
        echo "Please check BlueCat documentation or specify dns_server_id manually" >&2
    else
        echo "Found servers to deploy to: $server_ids" >&2
        
        # Deploy to each server
        for server_id in $server_ids; do
            echo "Deploying to server ID: $server_id" >&2
            
            # Use v2 deployment endpoint
            echo "Deploying to server $server_id using v2 API..." >&2
            deploy_result=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
                -X POST "$BASE_API_URL/deployments" \
                -H "$auth_header" \
                -H "Content-Type: application/json" \
                -d "{\"serverId\":$server_id,\"entityId\":$zone_id}")
            
            http_code=$(echo "$deploy_result" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
            deploy_body=$(echo "$deploy_result" | sed '/HTTP_CODE:/d')
            
            echo "Server $server_id - HTTP Code: $http_code" >&2
            echo "Server $server_id - Response: $deploy_body" >&2
            
            if [ "$http_code" = "200" ] || [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
                echo "✓ Successfully deployed to server $server_id" >&2
                deployment_status="deployed"
                if [ -z "$deployed_servers" ]; then
                    deployed_servers="$server_id"
                else
                    deployed_servers="$deployed_servers,$server_id"
                fi
            else
                echo "✗ Deployment to server $server_id failed. HTTP Code: $http_code" >&2
                echo "Response: $deploy_body" >&2
            fi
        done
    fi
fi
else
    echo "============================================" >&2
    echo "Auto-deployment disabled - skipping deployment" >&2
    echo "============================================" >&2
fi

echo "============================================" >&2
echo "Deployment phase completed: $deployment_status" >&2
echo "============================================" >&2

# --- Logout ---
curl -s -X DELETE "$BASE_API_URL/sessions/$token" -H "$auth_header" > /dev/null 2>&1
echo "Completed successfully" >&2

# Output JSON result to stdout for Terraform to capture (no jq needed)
# This is the ONLY output to stdout - everything else goes to stderr
printf '{"record_id":"%s","operation_status":"%s","fqdn":"%s","zone_id":"%s","deployment_status":"%s","deployed_servers":"%s"}\n' \
    "$final_record_id" "$operation_status" "$FQDN" "$zone_id" "$deployment_status" "$deployed_servers"