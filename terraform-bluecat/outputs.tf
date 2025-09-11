# Outputs for BlueCat DNS Record Management Module

output "record_id" {
  description = "Unique identifier for the DNS record"
  value       = local.record_id
}

output "status" {
  description = "Status of the DNS record operation"
  value       = local.operation_status
}

output "record_fqdn" {
  description = "Fully qualified domain name of the record"
  value       = "${var.record_name}.${var.zone}"
}

output "record_type" {
  description = "Type of the DNS record"
  value       = var.record_type
}

output "record_value" {
  description = "Value of the DNS record"
  value       = var.record_value
  sensitive   = false
}

output "ttl" {
  description = "Time to live of the DNS record"
  value       = var.ttl
}
