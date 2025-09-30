# BlueCat API Configuration Guide

## Response to Client Questions

### 1. Sample BlueCat URL Structure

**Our mock server URL for reference:**
```
http://localhost:5001
```

**Your production URL should follow this pattern:**
```
https://your-bluecat-server.domain.com
```

**Examples of what your URL might look like:**
- `https://bluecat.yourcompany.com`
- `https://bam.internal.company.com`  
- `https://dnsmanager.company.local`
- `https://xyz` (as your team mentioned)

### 2. API Version Support (v1 vs v2)

✅ **Yes, the module is now v2 by default!** We've fully migrated to v2 with v1 legacy support.

#### Standard BlueCat API Paths:
- **v2**: `/api/v2/` (current default)
- **v1**: `/Services/REST/v1/` (legacy support)

#### Your Team's Custom Path:
- **Custom**: `/api/v2/` (also supported!)

### 3. Sessions Endpoint Support

✅ **Yes, `/api/v2/sessions` makes perfect sense!**

BlueCat often uses different authentication endpoints for different API versions:
- **v1**: Uses `/Services/REST/v1/login`
- **v2**: Often uses `/Services/REST/v2/login` or `/api/v2/sessions`

We've updated the module to automatically detect and use the correct authentication endpoint based on your API path.

## Configuration Examples for Your Setup

### Option 1: Default v2 Configuration (Recommended)
```hcl
module "dns_record" {
  source = "./terraform-bluecat"

  api_url  = "https://your-bluecat-server.company.com"
  username = "your-username"  
  password = "your-password"
  # api_version = "v2"     # Default
  # api_path = "/api/v2"   # Default
  
  zone         = "your-domain.com"
  record_type  = "CNAME"
  record_name  = "test-record"
  record_value = "target.example.com"
  ttl          = 300
}
```

### Option 2: Custom API Path (For Specific Deployments)
```hcl
module "dns_record" {
  source = "./terraform-bluecat"

  api_url  = "https://xyz"          # Your base URL
  api_path = "/api/v2"              # Custom path (matches default)
  username = "your-username"
  password = "your-password"
  
  zone         = "your-domain.com"
  record_type  = "CNAME"
  record_name  = "test-record"
  record_value = "target.example.com"
  ttl          = 300
}
```

### Option 3: Legacy v1 Support
```hcl
module "dns_record" {
  source = "./terraform-bluecat"

  api_url     = "https://your-bluecat-server.company.com"
  api_version = "v1"       # Legacy v1 API
  api_path    = ""         # Use standard v1 path
  username    = "your-username"
  password    = "your-password"
  
  zone         = "your-domain.com"
  record_type  = "CNAME"
  record_name  = "test-record"
  record_value = "target.example.com"
  ttl          = 300
}
```

## How the Module Handles Different Configurations

### URL Construction:
- **Default v2**: `https://xyz/api/v2` (default configuration)
- **Legacy v1**: `https://xyz/Services/REST/v1`
- **Custom path**: `https://xyz/api/v2` (same as default)

### Authentication Endpoints:
- **v2 APIs**: Uses `POST /sessions` endpoint
- **v1 APIs**: Uses `GET /login` endpoint  
- **Result for v2**: `https://xyz/api/v2/sessions`

### API Endpoints Used:
- Authentication: `/sessions` (for your custom path)
- Zone lookup: `/getZonesByHint`
- Record operations: `/addHostRecord`, `/update`, `/delete`
- Deployment: `/quickDeploy`

## Testing Your Configuration

1. **Start with our mock server** to test the module structure
2. **Update the URL** to point to your BlueCat server  
3. **Use your team's configuration**:
   ```hcl
   api_url  = "https://xyz"
   api_path = "/api/v2"
   ```
4. **Test authentication** first with a simple record creation
5. **Verify all operations** work with your specific setup

## Next Steps

1. **Get your exact BlueCat server URL** from your team
2. **Confirm the authentication endpoint** (`/api/v2/sessions`)
3. **Test with the updated module** using Option 2 above
4. **Let us know if any adjustments are needed** for your specific API implementation

The module is now fully flexible and should work with your team's v2 API and sessions endpoint!
