output "record_id" {
  description = "The ID of the created/updated DNS record"
  value       = local.record_id
}

output "operation_status" {
  description = "Whether the record was created or updated"
  value       = local.operation_status
}

output "fqdn" {
  description = "Fully qualified domain name"
  value       = local.fqdn
}

output "zone_id" {
  description = "The zone ID where the record was created"
  value       = local.zone_id
}

output "deployment_status" {
  description = "Deployment status: 'deployed' or 'not_deployed'"
  value       = local.deployment_status
}

output "deployed_servers" {
  description = "Comma-separated list of DNS server IDs where the record was deployed"
  value       = local.deployed_servers
}

output "record_details" {
  description = "Complete record information including deployment status"
  value = {
    record_id         = local.record_id
    operation_status  = local.operation_status
    fqdn              = local.fqdn
    zone_id           = local.zone_id
    record_type       = var.record_type
    record_value      = var.record_value
    ttl               = var.ttl
    deployment_status = local.deployment_status
    deployed_servers  = local.deployed_servers
  }
}