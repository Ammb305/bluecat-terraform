# Test configuration for BlueCat DNS module
module "test_cname" {
  source = "../terraform-bluecat"

  # Connection settings
  api_url  = "http://localhost:5001"
  username = "testuser"
  password = "testpass"

  # Zone configuration
  zone = "queue.core.windows.net"

  # CNAME Record
  record_name  = "steus2ccanon123"
  record_type  = "CNAME"
  record_value = "steus2ccanon123.privatelink.queue.core.windows.net"
  ttl          = 300
}

# Output the results
output "record_id" {
  value = module.test_cname.record_id
}

output "status" {
  value = module.test_cname.operation_status
}

output "record_fqdn" {
  value = module.test_cname.fqdn
}
