# Test example using the mock server

terraform {
  required_version = ">= 1.0"
}

# Test CNAME Record
module "test_cname_record" {
  source = "../terraform-bluecat"

  api_url      = "http://localhost:5001"
  username     = "testuser"
  password     = "testpass"
  zone         = "queue.core.windows.net"
  record_type  = "CNAME"
  record_name  = "steus2ccanon123"
  record_value = "steus2ccanon123.privatelink.queue.core.windows.net"
  ttl          = 3600
}

# Test A Record (simulating the TXT record use case)
module "test_a_record" {
  source = "../terraform-bluecat"

  api_url      = "http://localhost:5001"
  username     = "testuser"
  password     = "testpass"
  zone         = "privatelink.queue.core.windows.net"
  record_type  = "A"
  record_name  = "steus2ccanon123"
  record_value = "10.127.21.121"
  ttl          = 3600
}

# Test TXT Record
module "test_txt_record" {
  source = "../terraform-bluecat"

  api_url      = "http://localhost:5001"
  username     = "testuser"
  password     = "testpass"
  zone         = "example.com"
  record_type  = "TXT"
  record_name  = "test-verification"
  record_value = "google-site-verification=abc123"
  ttl          = 300
}

# Outputs
output "test_results" {
  value = {
    cname_record = {
      id     = module.test_cname_record.record_id
      status = module.test_cname_record.operation_status
      fqdn   = module.test_cname_record.fqdn
    }
    a_record = {
      id     = module.test_a_record.record_id
      status = module.test_a_record.operation_status
      fqdn   = module.test_a_record.fqdn
    }
    txt_record = {
      id     = module.test_txt_record.record_id
      status = module.test_txt_record.operation_status
      fqdn   = module.test_txt_record.fqdn
    }
  }
}
