locals {
  cloud_init_config = templatefile("${path.module}/cloud-init.tpl", {
    ssh_public_key      = var.vm_ssh_public_key
    minio_root_user     = var.minio_root_user
    minio_root_password = var.minio_root_password
  })
}

resource "proxmox_virtual_environment_vm" "iapetus" {
  name      = "iapetus"
  node_name = "ceres"
  vm_id     = 200

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "canterbury"
    size          = 40
    interface     = "scsi0"
    import_from = proxmox_download_file.debian_cloud_image.id
  }

  network_device = [{
    bridge       = "vmbr0"
    disconnected = null
    enabled      = null
    firewall     = null
    mac_address  = null
    model        = null
    mtu          = null
    queues       = null
    rate_limit   = null
    trunks       = null
    vlan_id      = null
  }]

  initialization {
    datastore_id = "canterbury"
    ip_config {
      ipv4 {
        address = "10.10.10.24/24"
        gateway = "10.10.10.1"
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
  }

  operating_system {
    type = "l26"
  }
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "ceres"

  source_raw {
    data      = local.cloud_init_config
    file_name = "iapetus-cloud-init.yaml"
  }
}

resource "proxmox_download_file" "debian_cloud_image" {
  node_name    = "ceres"
  content_type = "import"
  datastore_id = "local"
  url          = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
  file_name    = "debian-12-generic-amd64.qcow2"
}