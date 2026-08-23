variable "nodes" {
  description = "Proxmox node names"
  type        = list(string)
  default     = ["ceres", "eros", "pallas"]
}

variable "pve_api_endpoint" {
  type = string
}

variable "pve_api_token" {
  type      = string
  sensitive = true
}