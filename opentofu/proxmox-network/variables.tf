variable "pve_api_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
}

variable "pve_api_token" {
  description = "Proxmox API token (reuses the same terraform@pve token as bootstrap-storage)"
  type        = string
  sensitive   = true
}

variable "nodes" {
  description = "Proxmox node names"
  type        = list(string)
  default     = ["ceres", "eros", "pallas"]
}