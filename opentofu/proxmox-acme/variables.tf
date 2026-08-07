variable "pve_api_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
}

variable "pve_root_password" {
  description = "Proxmox root@pam password — required for ACME resources, which don't support API token auth"
  type        = string
  sensitive   = true
}

variable "cloudflare_acme_token" {
  description = "Cloudflare API token for Proxmox's ACME DNS-01 plugin (same token already in use, being brought under SOPS management)"
  type        = string
  sensitive   = true
}