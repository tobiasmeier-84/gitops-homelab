resource "proxmox_node_disk_zfs" "razorback" {
  for_each = toset(var.nodes)

  node_name = each.value
  name      = "razorback"
  raidlevel = "single"
  devices   = ["/dev/${var.razorback_disk_id[each.value]}"]
}

resource "proxmox_storage_zfspool" "razorback" {
  id       = "razorback"
  nodes    = var.nodes
  zfs_pool = "razorback"
  content  = ["images"]

  depends_on = [proxmox_node_disk_zfs.razorback]
}

# ============================================================================
# TACHI: ceres only. mimas/rhea migrated to direct raw-disk passthrough for
# Longhorn's "fast" tier 2026-09-30 (real, controlled testing showed this
# resolves a replica-ejection pattern traced to ZFS+zvol write latency on
# the Patriot SSD and, by extension, this pool's own zvol architecture —
# see ADR-0005 addendum). Only enceladus (ceres) retains the original
# zvol-backed tachi disk, migration pending.
# ============================================================================
resource "proxmox_node_disk_zfs" "tachi" {
  for_each = toset(["ceres"])

  node_name = each.value
  name      = "tachi"
  raidlevel = "single"
  devices   = ["/dev/${var.tachi_disk_id[each.value]}"]
}

resource "proxmox_storage_zfspool" "tachi" {
  id       = "tachi"
  nodes    = ["ceres"]
  zfs_pool = "tachi"
  content  = ["images"]

  depends_on = [proxmox_node_disk_zfs.tachi]
}

# ============================================================================
# CANTERBURY: REMOVED 2026-09-30. All three nodes (enceladus/mimas/rhea)
# migrated to direct raw-disk passthrough for Longhorn's "general"/"slow"
# tiers, replacing the striped canterbury zpool entirely — see ADR-0005
# addendum. The pool no longer exists on any node.
# ============================================================================

# ============================================================================
# Enables the 'snippets' and 'import' content types on each node's default
# 'local' storage — required for cloud-init file uploads and cloud image
# downloads (discovered while building bootstrap-minio). Not enabled by
# default on a fresh Proxmox install.
# ============================================================================
resource "null_resource" "local_storage_content" {
  for_each = toset(var.nodes)

  triggers = {
    node = each.value
  }

  connection {
    type  = "ssh"
    host  = "${each.value}.belt.solsys.dev"
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "pvesm set local --content iso,vztmpl,backup,snippets,import"
    ]
  }
}

# ============================================================================
# SCRATCH-USB: REMOVED 2026-09-30. The physical USB disk suffered a
# permanent hardware failure (110,763 data errors, 2026-09-28 incident).
# Deliberately not rebuilt on replacement hardware — the backup pipeline
# redesign no longer depends on this dedicated disk. See ADR-0005 addendum.
# ============================================================================

# ============================================================================
# Caps ZFS ARC (Adaptive Replacement Cache) at 8GB per node. Uncapped, ARC
# can grow to 50% of host RAM by default — left unchecked, this would eat
# into the RAM budget allocated for VMs (RKE2 nodes at 24GB, titan, and
# iapetus on ceres). Applied to all 3 nodes regardless of the pallas SFP+
# situation, since this is host-wide memory management, unrelated to any
# specific storage link.
#
# Two-part change: /etc/modprobe.d/zfs.conf makes it persistent across
# reboots (requires update-initramfs, since ZFS loads via initramfs on a
# ZFS-root system); the live /sys/module write applies it immediately
# without waiting for a reboot. The live write can fail harmlessly if
# current ARC usage already exceeds the new cap on some ZFS versions —
# `|| true` handles that; the modprobe.d change still enforces it at the
# next reboot regardless.
# ============================================================================
resource "null_resource" "zfs_arc_cap" {
  for_each = toset(var.nodes)

  connection {
    type  = "ssh"
    host  = "${each.value}.belt.solsys.dev"
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'options zfs zfs_arc_max=8589934592' > /etc/modprobe.d/zfs.conf",
      "echo 8589934592 > /sys/module/zfs/parameters/zfs_arc_max || true",
      "update-initramfs -u"
    ]
  }
}
