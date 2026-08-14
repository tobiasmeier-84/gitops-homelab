variable "tenant_id" {
  description = "toebel.ch Entra ID tenant ID — not sensitive (a discoverable identifier, not a credential), set via terraform.tfvars"
  type        = string
}

variable "admin_upn" {
  description = "Your Entra ID User Principal Name (UPN) — the identity that becomes Captain on belt/agatha-king"
  type        = string
}