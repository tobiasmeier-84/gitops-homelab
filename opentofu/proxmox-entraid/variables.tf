variable "pve_api_endpoint" {
  type = string
}

variable "pve_root_password" {
  type      = string
  sensitive = true
}

variable "entraid_client_secret" {
  description = "Client secret for the Proxmox App Registration in Entra ID (reused from proxmox-host/secrets/entraid-oidc.enc.yaml, originally set up manually)"
  type        = string
  sensitive   = true
}