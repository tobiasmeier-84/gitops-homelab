variable "nodes" {
  description = "Proxmox node names"
  type        = list(string)
  default     = ["ceres", "eros", "pallas"]
}