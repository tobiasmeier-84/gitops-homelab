# ============================================================================
# VERIFY BEFORE APPLYING (not yet confirmed against live schema):
#   - dynamic "disk" for_each over a list: .key/.value semantics for
#     picking "first disk gets import_from" — confirm with `tofu plan`
#     before trusting the disk.key == 0 comparison below.
#   - ip_config block count must match network_device list length exactly
#     (positional correlation, confirmed via schema, but not yet tested
#     end-to-end with more than 1 NIC).
#   - Every network_device entry needs ALL object fields present, null
#     for unset ones — confirmed pattern from iapetus, reapplied here.
# ============================================================================

locals {
  cloud_init_config = templatefile("${path.module}/cloud-init.tpl", {
    ssh_public_key = var.ssh_public_key
    hostname       = var.name
  })

  network_devices = [
    for nic in var.network_interfaces : {
      bridge       = nic.bridge
      disconnected = null
      enabled      = null
      firewall     = null
      mac_address  = null
      model        = null
      mtu          = try(nic.mtu, null)
      queues       = null
      rate_limit   = null
      trunks       = null
      vlan_id      = null
    }
  ]
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    data      = local.cloud_init_config
    file_name = "${var.name}-cloud-init.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node_name
  vm_id     = var.vm_id

  cpu {
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory_mb
  }

  dynamic "disk" {
    for_each = { for idx, d in var.disks : idx => d }
    content {
      datastore_id = disk.value.datastore_id
      size         = disk.value.size
      interface    = disk.value.interface
      import_from = disk.key == "0" ? var.image_file_id : null
    }
  }

  network_device = local.network_devices

  serial_device {
    device = "socket"
  }

  initialization {
    datastore_id = var.disks[0].datastore_id

    dns {
      servers = ["10.10.10.53", "10.10.10.54"]
      domain  = "orbit.solsys.dev"
    }

    dynamic "ip_config" {
      for_each = var.network_interfaces
      content {
        ipv4 {
          address = ip_config.value.address
          gateway = try(ip_config.value.gateway, null)
        }
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
  }

  operating_system {
    type = "l26"
  }
}