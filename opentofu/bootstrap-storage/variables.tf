variable "pve_api_endpoint" {
  description = "Proxmox API endpoint, e.g. https://ceres.belt.solsys.dev:8006/"
  type        = string
}

variable "pve_api_token" {
  description = "Proxmox API token for the dedicated terraform@pve user, format: USER@REALM!TOKENID=UUID"
  type        = string
  sensitive   = true
}

variable "nodes" {
  description = "Proxmox node names to create storage pools on"
  type        = list(string)
  default     = ["ceres", "eros", "pallas"]
}

variable "razorback_disk_id" {
  description = "Per-node first NVMe disk identifier for the 'razorback' pool (single disk, no redundancy) — general fast tier for the RKE2 VM's root/etcd disk. Format TBD — verify against proxmox_virtual_environment_node_disk_zfs schema."
  type        = map(string)
}

variable "tachi_disk_id" {
  description = "Per-node second NVMe disk identifier for the 'tachi' pool (single disk, no redundancy). Dedicated fast tier for Nextcloud's database volume specifically — named for Rocinante's original name, tied to the workload this pool serves. Same format caveat as razorback_disk_id."
  type        = map(string)
}

variable "sata_disk_ids" {
  description = "Per-node list of the 3 remaining SATA SSD identifiers for the 'canterbury' pool (striped, non-redundant — Longhorn provides cross-node redundancy). Same format caveat as razorback_disk_id."
  type        = map(list(string))
}