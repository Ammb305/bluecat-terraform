# Variables for BlueCat DNS Record Management Module

variable "api_url" {
  description = "Base API endpoint for BlueCat server"
  type        = string
  validation {
    condition     = can(regex("^https?://", var.api_url))
    error_message = "The api_url must be a valid HTTP or HTTPS URL."
  }
}

variable "username" {
  description = "Username for BlueCat authentication"
  type        = string
  sensitive   = true
}

variable "password" {
  description = "Password for BlueCat authentication"
  type        = string
  sensitive   = true
}

variable "zone" {
  description = "Domain zone for DNS records (e.g., example.com)"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.zone))
    error_message = "The zone must be a valid domain name."
  }
}

variable "record_type" {
  description = "Type of DNS record to manage (CNAME or TXT)"
  type        = string
  validation {
    condition     = contains(["CNAME", "TXT", "A"], var.record_type)
    error_message = "Record type must be either CNAME, TXT, or A."
  }
}

variable "record_name" {
  description = "Name of the DNS record"
  type        = string
}

variable "record_value" {
  description = "Value of the DNS record"
  type        = string
}

variable "ttl" {
  description = "Time to live for the DNS record in seconds"
  type        = number
  default     = 3600
  validation {
    condition     = var.ttl >= 300 && var.ttl <= 86400
    error_message = "TTL must be between 300 and 86400 seconds."
  }
}

variable "timeout" {
  description = "Timeout for API requests in seconds"
  type        = number
  default     = 30
}
