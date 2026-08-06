variable "b2_management_key_id" {
  description = "Application Key ID for the dedicated OpenTofu management key (all-bucket access) — NOT the narrowly-scoped state-backup key"
  type        = string
  sensitive   = true
}

variable "b2_management_key" {
  description = "Application Key secret for the OpenTofu management key"
  type        = string
  sensitive   = true
}