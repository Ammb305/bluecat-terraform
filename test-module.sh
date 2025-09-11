#!/bin/bash

# BlueCat Terraform Module Test Script
# This script tests the module with the mock server

set -e

echo "=== BlueCat Terraform Module Test ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    case $1 in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $2"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $2"
            ;;
        "INFO")
            echo -e "${YELLOW}[INFO]${NC} $2"
            ;;
    esac
}

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    print_status "ERROR" "Python 3 is required but not installed."
    exit 1
fi

# Check if Terraform is available
if ! command -v terraform &> /dev/null; then
    print_status "ERROR" "Terraform is required but not installed."
    exit 1
fi

print_status "INFO" "Starting BlueCat mock server..."

# Start mock server in background
cd mock-server
python3 -m pip install -r requirements.txt --quiet
python3 server.py &
SERVER_PID=$!
cd ..

# Wait for server to start
sleep 3

# Check if server is running
if curl -s http://localhost:5000/health > /dev/null; then
    print_status "SUCCESS" "Mock server started successfully (PID: $SERVER_PID)"
else
    print_status "ERROR" "Failed to start mock server"
    kill $SERVER_PID 2>/dev/null || true
    exit 1
fi

# Function to cleanup
cleanup() {
    print_status "INFO" "Cleaning up..."
    kill $SERVER_PID 2>/dev/null || true
    cd examples
    terraform destroy -auto-approve -var-file=test.tfvars 2>/dev/null || true
    rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
    rm -rf .terraform/
    cd ..
}

# Set trap to cleanup on exit
trap cleanup EXIT

print_status "INFO" "Preparing test configuration..."

# Create test variables file
cd examples
cat > test.tfvars << EOF
# Test variables for mock server
# These are safe to commit as they're only for the mock server
api_url = "http://localhost:5000"
username = "testuser"
password = "testpass"
EOF

print_status "INFO" "Initializing Terraform..."
terraform init

print_status "INFO" "Running Terraform plan..."
if terraform plan -var-file=test.tfvars -out=testplan; then
    print_status "SUCCESS" "Terraform plan completed successfully"
else
    print_status "ERROR" "Terraform plan failed"
    exit 1
fi

print_status "INFO" "Applying Terraform configuration..."
if terraform apply -auto-approve testplan; then
    print_status "SUCCESS" "Terraform apply completed successfully"
else
    print_status "ERROR" "Terraform apply failed"
    exit 1
fi

print_status "INFO" "Checking outputs..."
terraform output test_results

print_status "INFO" "Verifying records in mock server..."
echo ""
echo "Mock server records:"
curl -s http://localhost:5000/debug/records | python3 -m json.tool

print_status "INFO" "Testing update operation..."
# Modify a record and apply again
sed -i.bak 's/ttl          = 300/ttl          = 600/' test-local.tf
terraform plan -var-file=test.tfvars -out=updateplan
terraform apply -auto-approve updateplan

print_status "SUCCESS" "Update operation completed"

print_status "INFO" "Testing destroy operation..."
if terraform destroy -auto-approve -var-file=test.tfvars; then
    print_status "SUCCESS" "Terraform destroy completed successfully"
else
    print_status "ERROR" "Terraform destroy failed"
    exit 1
fi

print_status "INFO" "Verifying cleanup..."
echo ""
echo "Mock server records after destroy:"
curl -s http://localhost:5000/debug/records | python3 -m json.tool

cd ..

print_status "SUCCESS" "All tests completed successfully!"
echo ""
echo "=== Test Summary ==="
echo "✅ Mock server started and responded correctly"
echo "✅ Terraform initialization successful"
echo "✅ Terraform plan generated without errors"
echo "✅ DNS records created successfully"
echo "✅ Record updates applied successfully" 
echo "✅ DNS records destroyed successfully"
echo ""
echo "The BlueCat Terraform module is ready for use!"
echo ""
echo "Next steps:"
echo "1. Replace mock server URL with your actual BlueCat server"
echo "2. Update credentials for your environment"
echo "3. Test with your actual DNS zones"
