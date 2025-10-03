output "record_id" {
  description = "The ID of the DNS record created or updated"
  value       = local.record_id
}

output "operation_status" {
  description = "The operation performed (created or updated)"
  value       = local.operation_status
}

output "fqdn" {
  description = "The fully qualified domain name of the record"
  value       = local.fqdn
}

output "zone_id" {
  description = "The zone ID where the record was created"
  value       = local.zone_id
}

output "record_details" {
  description = "Complete record details"
  value = {
    record_id        = local.record_id
    operation_status = local.operation_status
    fqdn             = local.fqdn
    zone_id          = local.zone_id
    record_type      = var.record_type
    record_value     = var.record_value
    ttl              = var.ttl
  }
}