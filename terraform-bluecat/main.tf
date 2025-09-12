terraform {
  required_version = ">= 1.0"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# DNS Record Management using external scripts
resource "null_resource" "dns_record_management" {
  triggers = {
    api_url      = var.api_url
    username     = var.username
    password     = var.password
    zone         = var.zone
    record_type  = var.record_type
    record_name  = var.record_name
    record_value = var.record_value
    ttl          = var.ttl
  }

  provisioner "local-exec" {
    command     = "${path.module}/manage_record.sh '${var.api_url}' '${var.username}' '${var.password}' '${var.zone}' '${var.record_type}' '${var.record_name}' '${var.record_value}' '${var.ttl}' '${path.module}' '${var.api_version}' '${var.api_path}'"
    interpreter = ["bash", "-c"]
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "${path.module}/delete_record.sh '${path.module}' '${self.triggers.api_url}' '${self.triggers.zone}' '${var.api_version}' '${var.api_path}'"
    interpreter = ["bash", "-c"]
  }
}

# Read the operation results
data "local_file" "record_id" {
  filename   = "${path.module}/.terraform_record_id"
  depends_on = [null_resource.dns_record_management]
}

data "local_file" "operation_status" {
  filename   = "${path.module}/.terraform_operation_status"
  depends_on = [null_resource.dns_record_management]
}

# Local values for outputs
locals {
  record_id        = try(trimspace(data.local_file.record_id.content), "")
  operation_status = try(trimspace(data.local_file.operation_status.content), "unknown")
}
