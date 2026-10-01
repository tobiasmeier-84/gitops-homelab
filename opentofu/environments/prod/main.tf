# ============================================================================
# Cloud image download — one per physical node, shared by every VM module
# call on that node (not re-downloaded per VM). Pinned to a specific dated
# snapshot for reproducibility.
# ============================================================================

resource "proxmox_download_file" "debian_ceres" {
  node_name    = "ceres"
  content_type = "import"
  datastore_id = "local"
  url          = "https://cloud.debian.org/images/cloud/bookworm/20260805-2561/debian-12-generic-amd64-20260805-2561.qcow2"
  file_name    = "debian-12-generic-amd64-20260805-2561-prod.qcow2"
}

# ============================================================================
# enceladus — RKE2 node 1, on ceres. First real test of the proxmox-vm
# module — 5 NICs (all VLANs), 3 disks (OS/etcd on razorback, bulk on
# canterbury, DB-tier on tachi). NIC order is MGMT, CLUSTER, STORAGE,
# DMZ-INGRESS, EGRESS — this ordering must stay consistent across every
# VM for net0-net4 to mean the same thing everywhere.
# ============================================================================

module "enceladus" {
  source = "../../modules/proxmox-vm"

  node_name      = "ceres"
  vm_id          = 201
  name           = "enceladus"
  cpu_cores      = 4
  memory_mb      = 32768
  image_file_id  = proxmox_download_file.debian_ceres.id
  ssh_public_key = var.vm_ssh_public_key

  disks = [
    { datastore_id = "razorback", size = 300, interface = "scsi0" },   # OS + etcd
    { datastore_id = "canterbury", size = 900, interface = "scsi1" }, # Longhorn bulk
    { datastore_id = "tachi", size = 100, interface = "scsi2" },       # Longhorn DB tier
  ]

  network_interfaces = [
    { bridge = "vmbr0", address = "10.10.10.41/24" },                                    # MGMT
    { bridge = "vmbr1", address = "10.10.20.41/24" },                                    # CLUSTER
    { bridge = "vmbr2", address = "10.10.30.41/24", mtu = 9000 },                        # STORAGE
    { bridge = "vmbr3", address = "10.10.40.41/24" },                                    # DMZ-INGRESS
    { bridge = "vmbr4", address = "10.10.50.41/24", gateway = "10.10.50.1" },            # EGRESS - carries default route
  ]
}

# ============================================================================
# Per-node cloud image downloads for eros and pallas (ceres's copy already
# exists above). Same pinned dated snapshot as enceladus, for consistency
# across all 3 nodes.
# ============================================================================

resource "proxmox_download_file" "debian_eros" {
  node_name    = "eros"
  content_type = "import"
  datastore_id = "local"
  url          = "https://cloud.debian.org/images/cloud/bookworm/20260805-2561/debian-12-generic-amd64-20260805-2561.qcow2"
  file_name    = "debian-12-generic-amd64-20260805-2561-prod.qcow2"
}

resource "proxmox_download_file" "debian_pallas" {
  node_name    = "pallas"
  content_type = "import"
  datastore_id = "local"
  url          = "https://cloud.debian.org/images/cloud/bookworm/20260805-2561/debian-12-generic-amd64-20260805-2561.qcow2"
  file_name    = "debian-12-generic-amd64-20260805-2561-prod.qcow2"
}

# ============================================================================
# mimas — RKE2 node 2, on eros.
#
# REBUILT 2026-09-30 after a real, serious incident: a manual `qm set`
# passthrough command pointed at the SAME physical NVMe (nvme0n1) that
# razorback's ZFS pool also used, causing real, permanent data corruption
# on mimas's own root disk (crashed etcd) and two OTHER, unrelated VMs
# sharing that same pool (deimos, nereid — both also rebuilt tonight).
# Root cause: raw device passthrough and ZFS pool membership on the same
# physical disk conflict directly — never assign a disk to both.
#
# Real, current eros disk inventory (confirmed via `ls -la
# /dev/disk/by-id/` cross-referenced against `zpool status`, 2026-09-30):
#   nvme0n1 (S3WTNX1M187076) = razorback (ZFS, this VM's own scsi0 — DO NOT PASSTHROUGH)
#   nvme1n1 (S36ENB0K201473) = free -> "fast" tier passthrough (scsi6)
#   sda (VK0480...501RE), sdb (VK0480...503E) = rpool mirror (Proxmox's own boot disk — DO NOT TOUCH)
#   sdc (Patriot), sdd/sde (VK0480 x2) = free -> "slow"/"general" passthrough
#
# Native path_in_datastore syntax (datastore_id = "", confirmed via
# provider docs 2026-09-30) replaces the earlier null_resource+qm
# workaround used on the first attempt — proper, idiomatic Terraform
# management, not an imperative side-channel. Real, controlled testing
# the same night validated this direct-attach architecture's stability
# (see ADR-0005 addendum) before this rebuild.
# ============================================================================

module "mimas" {
  source = "../../modules/proxmox-vm"

  node_name      = "eros"
  vm_id          = 202
  name           = "mimas"
  cpu_cores      = 4
  memory_mb      = 32768
  image_file_id  = proxmox_download_file.debian_eros.id
  ssh_public_key = var.vm_ssh_public_key

  disks = [
    { datastore_id = "razorback", size = 300, interface = "scsi0" },
    { datastore_id = "", interface = "scsi3", path_in_datastore = "/dev/disk/by-id/ata-Patriot_P210_1024GB_P210IICB25082903441", size = 953 }, # Direct passthrough, "slow" Longhorn tier
    { datastore_id = "", interface = "scsi4", path_in_datastore = "/dev/disk/by-id/ata-VK0480GDJXV_PHWL52650138480QGN", size = 447 }, # Direct passthrough, "general" Longhorn tier
    { datastore_id = "", interface = "scsi5", path_in_datastore = "/dev/disk/by-id/ata-VK0480GDJXV_PHWL505401K1480QGN", size = 447 }, # Direct passthrough, "general" Longhorn tier
    { datastore_id = "", interface = "scsi6", path_in_datastore = "/dev/disk/by-id/nvme-SAMSUNG_MZVLW512HMJP-000H1_S36ENB0K201473", size = 476 }, # Direct passthrough, "fast" Longhorn tier (former tachi)
  ]

  network_interfaces = [
    { bridge = "vmbr0", address = "10.10.10.42/24" },
    { bridge = "vmbr1", address = "10.10.20.42/24" },
    { bridge = "vmbr2", address = "10.10.30.42/24", mtu = 9000 },
    { bridge = "vmbr3", address = "10.10.40.42/24" },
    { bridge = "vmbr4", address = "10.10.50.42/24", gateway = "10.10.50.1" },
  ]
}

# ============================================================================
# rhea — RKE2 node 3, on pallas. Same shape as enceladus.
#
# NOTE: pallas's STORAGE NIC (vmbr2) has no working physical link yet —
# see docs/BACKLOG.md (SFP+ transceiver swap in progress). The bridge
# and this VM's NIC are still created/configured identically to the
# other two for consistency; it will simply carry no traffic until the
# hardware is fixed.
# ============================================================================

module "rhea" {
  source = "../../modules/proxmox-vm"

  node_name      = "pallas"
  vm_id          = 203
  name           = "rhea"
  cpu_cores      = 4
  memory_mb      = 32768
  image_file_id  = proxmox_download_file.debian_pallas.id
  ssh_public_key = var.vm_ssh_public_key

  disks = [
    { datastore_id = "razorback", size = 300, interface = "scsi0" },
    { datastore_id = "", interface = "scsi3", path_in_datastore = "/dev/disk/by-id/ata-Patriot_P210_1024GB_P210ZICB25080800055", size = 953 }, # Direct passthrough, "slow" Longhorn tier — see ADR-0005 addendum
    { datastore_id = "", interface = "scsi4", path_in_datastore = "/dev/disk/by-id/wwn-0x55cd2e404c4d826c", size = 447 }, # Direct passthrough, "general" Longhorn tier
    { datastore_id = "", interface = "scsi5", path_in_datastore = "/dev/disk/by-id/wwn-0x55cd2e404c58ccec", size = 447 }, # Direct passthrough, "general" Longhorn tier
    { datastore_id = "", interface = "scsi6", path_in_datastore = "/dev/disk/by-id/nvme-SAMSUNG_MZVLB512HAJQ-000H1_S3WTNX0M151107", size = 476 }, # Direct passthrough, "fast" Longhorn tier (former tachi)
  ]

  network_interfaces = [
    { bridge = "vmbr0", address = "10.10.10.43/24" },
    { bridge = "vmbr1", address = "10.10.20.43/24" },
    { bridge = "vmbr2", address = "10.10.30.43/24", mtu = 9000 },
    { bridge = "vmbr3", address = "10.10.40.43/24" },
    { bridge = "vmbr4", address = "10.10.50.43/24", gateway = "10.10.50.1" },
  ]
}

# ============================================================================
# HAProxy VRRP trio — triton/nereid/proteus, one per node. Much lighter
# than RKE2 nodes: 1 vCPU/2GB, single OS disk, only 2 NICs (MGMT,
# DMZ-INGRESS) — no CLUSTER/STORAGE/EGRESS, since these aren't k8s nodes.
# MGMT carries the default route here (gateway set), since there's no
# dedicated EGRESS leg on this VM role.
# ============================================================================

module "triton" {
  source = "../../modules/proxmox-vm"

  node_name      = "ceres"
  vm_id          = 210
  name           = "triton"
  cpu_cores      = 1
  memory_mb      = 2048
  image_file_id  = proxmox_download_file.debian_ceres.id
  ssh_public_key = var.vm_ssh_public_key

  disks = [
    { datastore_id = "razorback", size = 20, interface = "scsi0" },
  ]

  network_interfaces = [
    { bridge = "vmbr0", address = "10.10.10.31/24", gateway = "10.10.10.1" },
    { bridge = "vmbr3", address = "10.10.40.11/24" },
  ]
}

# ============================================================================
# nereid — REBUILT 2026-09-30, after real, permanent data corruption on
# this VM's razorback disk (same real incident described in mimas's
# comment above — a passthrough disk conflict on eros's shared NVMe
# corrupted every VM sharing that pool, including this one). Config
# below is unchanged from before the incident; razorback itself has
# since been destroyed and recreated clean (see bootstrap-storage).
# ============================================================================

module "nereid" {
  source = "../../modules/proxmox-vm"

  node_name      = "eros"
  vm_id          = 211
  name           = "nereid"
  cpu_cores      = 1
  memory_mb      = 2048
  image_file_id  = proxmox_download_file.debian_eros.id
  ssh_public_key = var.vm_ssh_public_key

  disks = [
    { datastore_id = "razorback", size = 20, interface = "scsi0" },
  ]

  network_interfaces = [
    { bridge = "vmbr0", address = "10.10.10.32/24", gateway = "10.10.10.1" },
    { bridge = "vmbr3", address = "10.10.40.12/24" },
  ]
}

module "proteus" {
  source = "../../modules/proxmox-vm"

  node_name      = "pallas"
  vm_id          = 212
  name           = "proteus"
  cpu_cores      = 1
  memory_mb      = 2048
  image_file_id  = proxmox_download_file.debian_pallas.id
  ssh_public_key = var.vm_ssh_public_key

  disks = [
    { datastore_id = "razorback", size = 20, interface = "scsi0" },
  ]

  network_interfaces = [
    { bridge = "vmbr0", address = "10.10.10.33/24", gateway = "10.10.10.1" },
    { bridge = "vmbr3", address = "10.10.40.13/24" },
  ]
}

# ============================================================================
# deimos — REBUILT 2026-09-30, after real, permanent data corruption on
# this VM's razorback disk (same real incident described in mimas's
# comment above). Config below is unchanged from before the incident;
# razorback itself has since been destroyed and recreated clean (see
# bootstrap-storage). This is the Pomerium ZTNA gateway — real, live
# access depends on it; verify reachability carefully after rebuild.
# ============================================================================

module "deimos" {
  source = "../../modules/proxmox-vm"

  node_name      = "eros"
  vm_id          = 220
  name           = "deimos"
  cpu_cores      = 1
  memory_mb      = 4096
  image_file_id  = proxmox_download_file.debian_eros.id
  ssh_public_key = var.vm_ssh_public_key

  disks = [
    { datastore_id = "razorback", size = 20, interface = "scsi0" },
  ]

  network_interfaces = [
    { bridge = "vmbr0", address = "10.10.10.34/24", gateway = "10.10.10.1" },
    { bridge = "vmbr3", address = "10.10.40.14/24" },
  ]
}

module "titania" {
  source = "../../modules/proxmox-vm"

  node_name      = "ceres"
  vm_id          = 222
  name           = "titania"
  cpu_cores      = 1
  memory_mb      = 2048
  image_file_id  = proxmox_download_file.debian_ceres.id
  ssh_public_key = var.vm_ssh_public_key

  disks = [
    { datastore_id = "razorback", size = 20, interface = "scsi0" },
  ]

  network_interfaces = [
    { bridge = "vmbr0", address = "10.10.10.53/24", gateway = "10.10.10.1" },
  ]
}

module "oberon" {
  source = "../../modules/proxmox-vm"

  node_name      = "pallas"
  vm_id          = 223
  name           = "oberon"
  cpu_cores      = 1
  memory_mb      = 2048
  image_file_id  = proxmox_download_file.debian_pallas.id
  ssh_public_key = var.vm_ssh_public_key

  disks = [
    { datastore_id = "razorback", size = 20, interface = "scsi0" },
  ]

  network_interfaces = [
    { bridge = "vmbr0", address = "10.10.10.54/24", gateway = "10.10.10.1" },
  ]
}
