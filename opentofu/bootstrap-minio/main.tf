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
    size         = 40
    interface    = "scsi0"
    import_from  = proxmox_virtual_environment_download_file.debian_cloud_image.id
  }

  serial_device {
    device = "socket"
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

resource "proxmox_virtual_environment_download_file" "debian_cloud_image" {
  node_name    = "ceres"
  content_type = "import"
  datastore_id = "local"
  url          = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
  file_name    = "debian-12-generic-amd64.qcow2"
}

# ============================================================================
# STATE BUCKET BACKUP: pushes the backup script + systemd timer to iapetus,
# templates out the (secret) rclone config + age recipient file separately
# via remote-exec heredocs. See ADR-0036.
#
# Gotchas fixed during initial provisioning (kept here as inline notes so
# they're not silently lost on a future edit):
#   - curl needs -L to follow redirects (both mc and rclone installers)
#   - rclone's installer needs `unzip` present, not included by default
#   - the script runs as root via systemd, so root needs its OWN `mc alias`
#     configured — the alias set on your local Mac during bucket setup
#     doesn't carry over to the VM
# ============================================================================
resource "null_resource" "state_backup_setup" {
  depends_on = [proxmox_virtual_environment_vm.iapetus]

  connection {
    type  = "ssh"
    host  = "iapetus.orbit.solsys.dev"
    user  = "admin"
    agent = true
  }

  provisioner "file" {
    source      = "${path.module}/scripts/state-backup.sh"
    destination = "/tmp/state-backup.sh"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/state-backup.service"
    destination = "/tmp/state-backup.service"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/state-backup.timer"
    destination = "/tmp/state-backup.timer"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /opt/state-backup /etc/state-backup",
      "sudo mv /tmp/state-backup.sh /opt/state-backup/state-backup.sh",
      "sudo chmod +x /opt/state-backup/state-backup.sh",
      "sudo mv /tmp/state-backup.service /etc/systemd/system/state-backup.service",
      "sudo mv /tmp/state-backup.timer /etc/systemd/system/state-backup.timer",
      "echo '${var.state_backup_age_public_key}' | sudo tee /etc/state-backup/age-recipient.txt > /dev/null",
      "sudo tee /etc/state-backup/rclone.conf > /dev/null <<'RCLONE_EOF'\n[b2-state-backup]\ntype = b2\naccount = ${var.b2_key_id}\nkey = ${var.b2_application_key}\nRCLONE_EOF",
      "sudo chmod 600 /etc/state-backup/rclone.conf /etc/state-backup/age-recipient.txt",
      "sudo apt-get update && sudo apt-get install -y curl age zstd unzip",
      "which mc >/dev/null || (curl -sL https://dl.min.io/client/mc/release/linux-amd64/mc -o /tmp/mc && sudo install /tmp/mc /usr/local/bin/mc)",
      "which rclone >/dev/null || (curl -sL https://rclone.org/install.sh | sudo bash)",
      "sudo mc alias set homelab http://localhost:9000 '${var.minio_root_user}' '${var.minio_root_password}'",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable --now state-backup.timer"
    ]
  }
}