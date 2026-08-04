resource "proxmox_node_disk_zfs" "razorback" {
  for_each = toset(var.nodes)

  node_name = each.value
  name      = "razorback"
  raidlevel = "single"
  devices   = ["/dev/${var.razorback_disk_id[each.value]}"]
}

resource "proxmox_node_disk_zfs" "tachi" {
  for_each = toset(var.nodes)

  node_name = each.value
  name      = "tachi"
  raidlevel = "single"
  devices   = ["/dev/${var.tachi_disk_id[each.value]}"]
}

# ============================================================================
# CANTERBURY: raw zpool creation via SSH, bypassing Proxmox's own ZFS
# creation API — that API's "single" raidlevel rejects more than 1 disk,
# so a genuine multi-disk stripe (no redundancy, max capacity) isn't
# reachable through proxmox_node_disk_zfs at all. Longhorn already
# provides redundancy at the cluster level (see ADR-0002), so host-level
# redundancy here (raidz1) would cost ~1/3 capacity for protection this
# design doesn't need.
#
# TRADE-OFF: this is an imperative provisioner, not a declarative resource
# — OpenTofu doesn't track its state the way it does proxmox_node_disk_zfs.
# Requires: local ssh-agent running with a key authorized for root on each
# node (same KeePassXC-backed SSH setup already in use elsewhere).
#
# The `zpool list ... || zpool create ...` pattern makes this idempotent —
# safe to re-run `tofu apply` without erroring if the pool already exists.
# ============================================================================
resource "null_resource" "canterbury_zpool" {
  for_each = toset(var.nodes)

  triggers = {
    node  = each.value
    disks = join(",", var.sata_disk_ids[each.value])
  }

  connection {
    type  = "ssh"
    host  = "${each.value}.belt.solsys.dev"
    user  = "root"
    agent = true  # uses local ssh-agent (KeePassXC-loaded key), no key file referenced here
  }

  provisioner "remote-exec" {
    inline = [
      "zpool list -H -o name | grep -qx canterbury || zpool create canterbury ${join(" ", [for d in var.sata_disk_ids[each.value] : "/dev/${d}"])}"
    ]
  }
}

resource "proxmox_storage_zfspool" "razorback" {
  id       = "razorback"
  nodes    = var.nodes
  zfs_pool = "razorback"
  content  = ["images"]

  depends_on = [proxmox_node_disk_zfs.razorback]
}

resource "proxmox_storage_zfspool" "tachi" {
  id       = "tachi"
  nodes    = var.nodes
  zfs_pool = "tachi"
  content  = ["images"]

  depends_on = [proxmox_node_disk_zfs.tachi]
}

resource "proxmox_storage_zfspool" "canterbury" {
  id       = "canterbury"
  nodes    = var.nodes
  zfs_pool = "canterbury"
  content  = ["images"]

  depends_on = [null_resource.canterbury_zpool]
}

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