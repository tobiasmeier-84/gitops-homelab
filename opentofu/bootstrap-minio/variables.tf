variable "pve_api_endpoint" {
  description = "Proxmox API endpoint, e.g. https://ceres.belt.solsys.dev:8006/"
  type        = string
}

variable "pve_api_token" {
  description = "Proxmox API token (reuses the same terraform@pve token as bootstrap-storage)"
  type        = string
  sensitive   = true
}

variable "vm_ssh_public_key" {
  description = "Public half of the dedicated VM admin SSH key (~/.ssh/id_ed25519_vms.pub) — baked into every VM via cloud-init going forward"
  type        = string
}

variable "minio_root_user" {
  description = "MinIO root/admin username"
  type        = string
  sensitive   = true
}

variable "minio_root_password" {
  description = "MinIO root/admin password"
  type        = string
  sensitive   = true
}