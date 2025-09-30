# BlueCat Terraform Module

A custom Terraform module for managing DNS records (CNAME, TXT, and A records) using BlueCat's REST API without relying on the official BlueCat Terraform provider.

## Features

- **Full CRUD Support**: Create, Read, Update, and Delete DNS records
- **Authentication Management**: Automatic token-based authentication with session cleanup
- **Multiple Record Types**: Support for CNAME, TXT, and A records
- **Error Handling**: Comprehensive error handling and logging
- **Local Testing**: Includes a mock server for local development and testing

## Module Structure

```
terraform-bluecat/
├── main.tf              # HTTP-based implementation (simpler)
├── crud_main.tf         # Full CRUD implementation with bash scripts
├── variables.tf         # Input variables
├── outputs.tf          # Output values
└── .gitignore          # Git ignore rules
```

## Requirements

- Terraform >= 1.0
- BlueCat Address Manager with REST API enabled
- Network connectivity to BlueCat server
- Valid BlueCat credentials

## Usage

### Basic Example

```hcl
module "dns_record" {
  source = "./terraform-bluecat"
  
  api_url      = "https://your-bluecat-server"
  username     = "your-username"
  password     = "your-password"
  zone         = "example.com"
  record_type  = "CNAME"
  record_name  = "test1"
  record_value = "test2.example.com"
  ttl          = 3600
}

output "record_details" {
  value = {
    record_id = module.dns_record.record_id
    status    = module.dns_record.status
    fqdn      = module.dns_record.record_fqdn
  }
}
```

### Multiple Records

```hcl
# CNAME Record
module "cname_record" {
  source = "./terraform-bluecat"
  
  api_url      = "https://your-bluecat-server"
  username     = var.username
  password     = var.password
  zone         = "queue.core.windows.net"
  record_type  = "CNAME"
  record_name  = "steus2ccanon123"
  record_value = "steus2ccanon123.privatelink.queue.core.windows.net"
}

# A Record
module "a_record" {
  source = "./terraform-bluecat"
  
  api_url      = "https://your-bluecat-server"
  username     = var.username
  password     = var.password
  zone         = "privatelink.queue.core.windows.net"
  record_type  = "A"
  record_name  = "steus2ccanon123"
  record_value = "10.127.21.121"
}

# TXT Record
module "txt_record" {
  source = "./terraform-bluecat"
  
  api_url      = "https://your-bluecat-server"
  username     = var.username
  password     = var.password
  zone         = "example.com"
  record_type  = "TXT"
  record_name  = "verification"
  record_value = "google-site-verification=abc123"
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| api_url | Base API endpoint for BlueCat server | `string` | n/a | yes |
| username | Username for BlueCat authentication | `string` | n/a | yes |
| password | Password for BlueCat authentication | `string` | n/a | yes |
| zone | Domain zone for DNS records | `string` | n/a | yes |
| record_type | Type of DNS record (CNAME, TXT, A) | `string` | n/a | yes |
| record_name | Name of the DNS record | `string` | n/a | yes |
| record_value | Value of the DNS record | `string` | n/a | yes |
| ttl | Time to live for the DNS record in seconds | `number` | `3600` | no |
| timeout | Timeout for API requests in seconds | `number` | `30` | no |
| api_version | BlueCat API version (v1 or v2) | `string` | `"v2"` | no |
| api_path | Custom API path (overrides version-based path) | `string` | `"/api/v2"` | no |

## API Version Support

The module supports both v1 and v2 APIs with flexible endpoint configuration:

### Standard BlueCat API Endpoints:
- **v1**: `https://your-server/Services/REST/v1`
- **v2**: `https://your-server/Services/REST/v2` (default)

### Custom API Endpoints:
- **Custom path**: `https://your-server/api/v2` (default configuration)
- **Sessions endpoint**: Automatically uses `/sessions` for v2 authentication

### URL Structure Examples:
```hcl
# Standard v2 (default)
api_url = "https://bluecat.company.com"
api_version = "v2"  # Optional, this is the default
api_path = "/api/v2"  # Optional, this is the default
# Results in: https://bluecat.company.com/api/v2
# Authentication: https://bluecat.company.com/api/v2/sessions

# Standard v1 (legacy)
api_url = "https://bluecat.company.com"
api_version = "v1"
api_path = ""
# Results in: https://bluecat.company.com/Services/REST/v1

# Custom API path
api_url = "https://xyz"
api_path = "/api/v2"
# Results in: https://xyz/api/v2
# Authentication: https://xyz/api/v2/sessions
```

## Outputs

| Name | Description |
|------|-------------|
| record_id | Unique identifier for the DNS record |
| status | Status of the DNS record operation (created/updated/unchanged) |
| record_fqdn | Fully qualified domain name of the record |
| record_type | Type of the DNS record |
| record_value | Value of the DNS record |
| ttl | Time to live of the DNS record |

## Local Testing

The module includes a mock BlueCat API server for local testing and development.

### Starting the Mock Server

1. Install Python dependencies:
```bash
cd mock-server
pip install -r requirements.txt
```

2. Start the mock server:
```bash
python server.py
```

The server will run on `http://localhost:5001` and accept any username/password combination.

### Running Tests

1. Use the test configuration:
```bash
cd examples
cp test-local.tf main.tf
terraform init
terraform plan
terraform apply
```

2. Check the results:
```bash
terraform output test_results
```

### Mock Server Endpoints

The mock server provides the following endpoints for testing:

**v2 API Endpoints (default):**
- `POST /api/v2/sessions` - Authentication
- `GET /api/v2/logout` - Session cleanup
- `GET /api/v2/getZonesByHint` - Zone lookup
- `GET /api/v2/zones/{id}/entities` - Get zone entities
- `POST /api/v2/zones/{id}/entities` - Create records
- `PUT /api/v2/entities/{id}` - Update records
- `DELETE /api/v2/entities/{id}` - Delete records
- `POST /api/v2/quickDeploy` - Deploy changes

**v1 API Endpoints (legacy):**
- `GET /Services/REST/v1/login` - Authentication
- `GET /Services/REST/v1/logout` - Session cleanup
- `GET /Services/REST/v1/getZonesByHint` - Zone lookup
- `GET /Services/REST/v1/getHostRecordsByHint` - Record lookup
- `POST /Services/REST/v1/addHostRecord` - Create records
- `PUT /Services/REST/v1/update` - Update records
- `DELETE /Services/REST/v1/delete` - Delete records
- `POST /Services/REST/v1/quickDeploy` - Deploy changes

**Debug Endpoints:**
- `GET /health` - Health check
- `GET /debug/records` - View all records

## Implementation Details

### Authentication

The module automatically handles authentication by:
1. Generating a token using username/password via REST API
2. Using the token in all subsequent API requests
3. Cleaning up the session on resource destruction

### CRUD Operations

- **Create**: Adds new DNS records if they don't exist
- **Read**: Checks for existing records before operations
- **Update**: Modifies existing records when values change
- **Delete**: Removes records during `terraform destroy`

### Error Handling

The module includes comprehensive error handling for:
- Authentication failures
- Invalid API responses
- Network connectivity issues
- Malformed requests
- Missing resources

## Troubleshooting

### Common Issues

1. **Authentication Failed**
   - Verify BlueCat server URL is correct and accessible
   - Check username and password are valid
   - Ensure REST API is enabled on BlueCat server

2. **Zone Not Found**
   - Verify the zone exists in BlueCat
   - Check zone name spelling and case sensitivity
   - Ensure proper permissions for the zone

3. **Record Creation Failed**
   - Check if record already exists with different values
   - Verify record type and value format are correct
   - Ensure sufficient permissions for record creation

4. **Deployment Issues**
   - Deployment failures are treated as warnings and don't fail the operation
   - Records are created/updated even if deployment fails
   - Manual deployment may be required in BlueCat GUI

### Debug Mode

For troubleshooting, you can:

1. Enable Terraform debug logging:
```bash
export TF_LOG=DEBUG
terraform apply
```

2. Check mock server debug endpoints:
```bash
curl http://localhost:5001/health
curl http://localhost:5001/debug/records
```

## Security Considerations

- Store credentials securely using environment variables or Terraform Cloud
- Use HTTPS for all API communications in production
- Implement proper access controls in BlueCat
- Consider using service accounts with minimal required permissions

## Limitations

- Requires direct network connectivity to BlueCat server
- Token expiration handling is basic (1-hour timeout)
- Limited to basic DNS record types (CNAME, TXT, A)
- Deployment is best-effort and may require manual intervention

## Contributing

1. Test changes with the mock server
2. Ensure all record types work correctly
3. Update documentation for any new features
4. Test with actual BlueCat server if possible
