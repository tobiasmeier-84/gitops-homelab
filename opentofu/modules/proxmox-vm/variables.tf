variable "node_name" {
  description = "Proxmox node to create this VM on"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID (must be unique cluster-wide)"
  type        = number
}

variable "name" {
  description = "VM name (also used as hostname)"
  type        = string
}

variable "cpu_cores" {
  description = "vCPU core count"
  type        = number
  default     = 4
}

variable "memory_mb" {
  description = "RAM in MB"
  type        = number
  default     = 24576
}

variable "image_file_id" {
  description = "ID of an already-downloaded cloud image on this node (from a proxmox_download_file resource in the calling environment), used as the source for the first disk"
  type        = string
}

variable "ssh_public_key" {
  description = "Public half of the VM admin SSH key (~/.ssh/id_ed25519_vms.pub)"
  type        = string
}

variable "disks" {
  description = "VM disks, in order. The FIRST disk is imported from image_file_id (OS disk); subsequent disks are blank (e.g. for Longhorn)."
  type = list(object({
    datastore_id = string
    size         = number
    interface    = string
  }))
}

variable "network_interfaces" {
  description = "NICs in order. network_device and ip_config are correlated positionally by the provider, so order matters — must match the intended net0/net1/... numbering."
  type = list(object({
    bridge  = string
    address = string
    gateway = optional(string)
    mtu     = optional(number)
  }))
}