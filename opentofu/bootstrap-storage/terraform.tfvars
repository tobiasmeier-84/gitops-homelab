# Copy to terraform.tfvars and fill in real values, then COMMIT the result —
# disk identifiers are hardware data, not secrets (same precedent as
# proxmox-host/nodes.yaml). The actual secret (API token) is handled
# separately via SOPS + TF_VAR_pve_api_token, never in this file.

razorback_disk_id = {
  ceres  = "nvme0n1"
  eros   = "nvme0n1"
  pallas = "nvme0n1"
}

tachi_disk_id = {
  ceres  = "nvme1n1"
  eros   = "nvme1n1"
  pallas = "nvme1n1"
}

sata_disk_ids = {
  ceres  = ["sdc", "sdd", "sde"]
  eros   = ["sdc", "sdd", "sde"]
  pallas = ["sdc", "sdd", "sde"]
}

scratch_usb_disk_id = "disk/by-id/usb-BUSLINK_Ciphershield_1208010000F04000026-0:0"