terraform {
  required_version = ">= 1.0"
  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Use external data source to execute script and capture output
# This replaces the local file approach which fails in Azure DevOps ephemeral agents
data "external" "dns_record" {
  program = ["bash", "${path.module}/manage_record.sh"]

  query = {
    api_url       = var.api_url
    username      = var.username
    password      = var.password
    zone          = var.zone
    record_type   = var.record_type
    record_name   = var.record_name
    record_value  = var.record_value
    ttl           = tostring(var.ttl)
    api_version   = var.api_version
    api_path      = var.api_path
    dns_server_id = var.dns_server_id
    auto_deploy   = tostring(var.auto_deploy)
  }
}

# Null resource for destroy operation only
# The record_id from external data is included in triggers to ensure proper lifecycle
resource "null_resource" "dns_record_destroy" {
  triggers = {
    # Variables needed for destroy
    api_url      = var.api_url
    username     = var.username
    password     = var.password
    zone         = var.zone
    record_type  = var.record_type
    record_name  = var.record_name
    api_version  = var.api_version
    api_path     = var.api_path
    auto_deploy  = tostring(var.auto_deploy)
    
    record_id    = data.external.dns_record.result.record_id
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "echo '{\"api_url\":\"${self.triggers.api_url}\",\"username\":\"${self.triggers.username}\",\"password\":\"${self.triggers.password}\",\"zone\":\"${self.triggers.zone}\",\"record_type\":\"${self.triggers.record_type}\",\"record_name\":\"${self.triggers.record_name}\",\"record_id\":\"${self.triggers.record_id}\",\"api_path\":\"${self.triggers.api_path}\",\"auto_deploy\":\"${try(self.triggers.auto_deploy, "true")}\"}' | ${path.module}/delete_record.sh"
    interpreter = ["bash", "-c"]
  }
}

# Local values for outputs - data comes directly from external data source result
# No local files needed - all data is in Terraform state
locals {
  record_id         = data.external.dns_record.result.record_id
  operation_status  = data.external.dns_record.result.operation_status
  fqdn              = data.external.dns_record.result.fqdn
  zone_id           = data.external.dns_record.result.zone_id
  deployment_status = data.external.dns_record.result.deployment_status
  deployed_servers  = data.external.dns_record.result.deployed_servers
}