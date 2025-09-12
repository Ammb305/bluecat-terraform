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

✅ **Yes, the module fully supports v2!** We've updated it to handle both versions.

#### Standard BlueCat API Paths:
- **v1**: `/Services/REST/v1/` (our current default)
- **v2**: `/Services/REST/v2/` (fully supported now)

#### Your Team's Custom Path:
- **Custom**: `/api/v2/` (also supported!)

### 3. Sessions Endpoint Support

✅ **Yes, `/api/v2/sessions` makes perfect sense!**

BlueCat often uses different authentication endpoints for different API versions:
- **v1**: Uses `/Services/REST/v1/login`
- **v2**: Often uses `/Services/REST/v2/login` or `/api/v2/sessions`

We've updated the module to automatically detect and use the correct authentication endpoint based on your API path.

## Configuration Examples for Your Setup

### Option 1: Standard v2 API
```hcl
module "dns_record" {
  source = "./terraform-bluecat"

  api_url     = "https://your-bluecat-server.company.com"
  username    = "your-username"  
  password    = "your-password"
  api_version = "v2"  # This will use /Services/REST/v2
  
  zone         = "your-domain.com"
  record_type  = "CNAME"
  record_name  = "test-record"
  record_value = "target.example.com"
  ttl          = 300
}
```

### Option 2: Your Team's Custom API Path  
```hcl
module "dns_record" {
  source = "./terraform-bluecat"

  api_url  = "https://xyz"          # Your base URL
  api_path = "/api/v2"              # Your custom path
  username = "your-username"
  password = "your-password"
  
  zone         = "your-domain.com"
  record_type  = "CNAME"
  record_name  = "test-record"
  record_value = "target.example.com"
  ttl          = 300
}
```

## How the Module Handles Different Configurations

### URL Construction:
- **Standard v1**: `https://xyz/Services/REST/v1`
- **Standard v2**: `https://xyz/Services/REST/v2`  
- **Custom path**: `https://xyz/api/v2`

### Authentication Endpoints:
- **Standard APIs**: Uses `/login` endpoint
- **Custom /api/v2**: Automatically uses `/sessions` endpoint
- **Result for your setup**: `https://xyz/api/v2/sessions`

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
