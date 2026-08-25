variable "azure_subscription_id" {
  description = "Azure subscription ID (pay-as-you-go)"
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant ID"
  type        = string
  default     = "0b87a43d-5640-4e22-a2f2-d13394ff6191"
}

variable "admin_object_id" {
  description = "Object ID of the operator's own account, granted Key Vault access"
  type        = string
}