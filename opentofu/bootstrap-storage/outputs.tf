output "storage_pool_ids" {
  description = "Storage pool IDs available for VM disk placement in the main environments/prod config"
  value = {
    razorback  = proxmox_storage_zfspool.razorback.id
    tachi      = proxmox_storage_zfspool.tachi.id
    canterbury = proxmox_storage_zfspool.canterbury.id
  }
}