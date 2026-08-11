variable "pve_api_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
}

variable "pve_api_token" {
  description = "Proxmox API token (reuses the same terraform@pve token as other configs)"
  type        = string
  sensitive   = true
}

variable "vm_ssh_public_key" {
  description = "Public half of the VM admin SSH key (~/.ssh/id_ed25519_vms.pub) — not secret, safe to commit"
  type        = string
}