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
  memory_mb      = 24576
  image_file_id  = proxmox_download_file.debian_ceres.id
  ssh_public_key = var.vm_ssh_public_key

  disks = [
    { datastore_id = "razorback", size = 40, interface = "scsi0" },   # OS + etcd
    { datastore_id = "canterbury", size = 1500, interface = "scsi1" }, # Longhorn bulk
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