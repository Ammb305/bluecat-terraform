variable "api_url" {
  description = "BlueCat API URL"
  type        = string
}

variable "username" {
  description = "BlueCat username"
  type        = string
  sensitive   = true
}

variable "password" {
  description = "BlueCat password"
  type        = string
  sensitive   = true
}

variable "zone" {
  description = "DNS zone name"
  type        = string
}

variable "record_type" {
  description = "DNS record type (A, AAAA, CNAME, TXT)"
  type        = string
  
  validation {
    condition     = contains(["A", "AAAA", "CNAME", "TXT"], var.record_type)
    error_message = "Record type must be one of: A, AAAA, CNAME, TXT"
  }
}

variable "record_name" {
  description = "DNS record name (without zone)"
  type        = string
}

variable "record_value" {
  description = "DNS record value (IP address, hostname, or text)"
  type        = string
}

variable "ttl" {
  description = "Time to live in seconds"
  type        = number
  default     = 300
}

variable "api_version" {
  description = "BlueCat API version"
  type        = string
  default     = "v2"
}

variable "api_path" {
  description = "BlueCat API path"
  type        = string
  default     = "/api/v2"
}

variable "dns_server_id" {
  description = "Optional: Specific DNS Server ID to deploy to. If not specified, auto-discovers servers from zone"
  type        = string
  default     = ""
}

variable "auto_deploy" {
  description = "Whether to automatically deploy DNS changes to servers after record creation/deletion"
  type        = bool
  default     = true
}