# ============================================================================
# VERIFY BEFORE APPLYING: proxmox_virtual_environment_node_disk_zfs was added
# in bpg/proxmox v0.111.0 (June 2026) — exact argument names below are a
# best-effort draft, not confirmed against full provider documentation.
# Check `tofu providers schema -json` or the live registry page for this
# resource before running `tofu apply`. In particular: the exact raid_level
# value for "striped, no redundancy" (used for "canterbury") and the
# expected device identifier format both need confirming.
# ============================================================================

resource "proxmox_virtual_environment_node_disk_zfs" "razorback" {
  for_each = toset(var.nodes)

  node_name  = each.value
  name       = "razorback"
  raid_level = "single"                  # single disk, no redundancy — VM disk, not host boot; etcd quorum + Longhorn replication mitigate
  devices    = [var.razorback_disk_id[each.value]]
}

resource "proxmox_virtual_environment_node_disk_zfs" "tachi" {
  for_each = toset(var.nodes)

  node_name  = each.value
  name       = "tachi"
  raid_level = "single"                  # single disk, no redundancy — same rationale as razorback
  devices    = [var.tachi_disk_id[each.value]]
}

resource "proxmox_virtual_environment_node_disk_zfs" "canterbury" {
  for_each = toset(var.nodes)

  node_name  = each.value
  name       = "canterbury"
  raid_level = "single"                  # VERIFY: intent is striped/no-redundancy across all 3 disks — confirm correct value
  devices    = var.sata_disk_ids[each.value]
}

resource "proxmox_storage_zfspool" "razorback" {
  id       = "razorback"
  nodes    = var.nodes
  zfs_pool = "razorback"
  content  = ["images"]

  depends_on = [proxmox_virtual_environment_node_disk_zfs.razorback]
}

resource "proxmox_storage_zfspool" "tachi" {
  id       = "tachi"
  nodes    = var.nodes
  zfs_pool = "tachi"
  content  = ["images"]

  depends_on = [proxmox_virtual_environment_node_disk_zfs.tachi]
}

resource "proxmox_storage_zfspool" "canterbury" {
  id       = "canterbury"
  nodes    = var.nodes
  zfs_pool = "canterbury"
  content  = ["images"]

  depends_on = [proxmox_virtual_environment_node_disk_zfs.canterbury]
}