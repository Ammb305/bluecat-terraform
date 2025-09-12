# BlueCat API Version Examples

## Example 1: Standard v1 API (Current Default)
module "dns_record_v1" {
  source = "./terraform-bluecat"

  # Your BlueCat server URL
  api_url  = "https://your-bluecat-server.company.com"
  username = "your-username"
  password = "your-password"
  
  # API version (optional, defaults to v1)
  api_version = "v1"
  # This will use: https://your-bluecat-server.company.com/Services/REST/v1
  
  # DNS record configuration
  zone         = "your-domain.com"
  record_type  = "CNAME"
  record_name  = "test-record"
  record_value = "target.example.com"
  ttl          = 300
}

## Example 2: Standard v2 API
module "dns_record_v2" {
  source = "./terraform-bluecat"

  # Your BlueCat server URL
  api_url  = "https://your-bluecat-server.company.com"
  username = "your-username"
  password = "your-password"
  
  # API version v2
  api_version = "v2"
  # This will use: https://your-bluecat-server.company.com/Services/REST/v2
  
  # DNS record configuration
  zone         = "your-domain.com"
  record_type  = "CNAME" 
  record_name  = "test-record"
  record_value = "target.example.com"
  ttl          = 300
}

## Example 3: Custom API Path (Your Team's Setup)
module "dns_record_custom" {
  source = "./terraform-bluecat"

  # Your BlueCat server URL (base URL only)
  api_url  = "https://xyz"
  username = "your-username"
  password = "your-password"
  
  # Custom API path (overrides version-based path)
  api_path = "/api/v2"
  # This will use: https://xyz/api/v2
  # Authentication will use: https://xyz/api/v2/sessions
  
  # DNS record configuration
  zone         = "your-domain.com"
  record_type  = "CNAME"
  record_name  = "test-record" 
  record_value = "target.example.com"
  ttl          = 300
}

## Example 4: Testing with Mock Server
module "dns_record_test" {
  source = "./terraform-bluecat"

  # Mock server for testing
  api_url  = "http://localhost:5001"
  username = "testuser"
  password = "testpass"
  
  # Test with v1 (default)
  api_version = "v1"
  
  # DNS record configuration
  zone         = "queue.core.windows.net"
  record_type  = "CNAME"
  record_name  = "steus2ccanon123"
  record_value = "steus2ccanon123.privatelink.queue.core.windows.net"
  ttl          = 300
}
