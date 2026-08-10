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
    import_from = proxmox_download_file.debian_cloud_image.id
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

resource "proxmox_download_file" "debian_cloud_image" {
  node_name    = "ceres"
  content_type = "import"
  datastore_id = "local"
  # Pinned to a specific dated snapshot rather than "latest" for
  # reproducibility — "latest" caused an unexpected replace when Debian
  # rolled the image forward mid-build. Bump this URL deliberately when
  # you want a newer base image, rather than it happening silently.
  url          = "https://cloud.debian.org/images/cloud/bookworm/20260805-2561/debian-12-generic-amd64-20260805-2561.qcow2"
  file_name    = "debian-12-generic-amd64-20260805-2561.qcow2"
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

  triggers = {
    script_hash  = filesha256("${path.module}/scripts/state-backup.sh")
    service_hash = filesha256("${path.module}/scripts/state-backup.service")
    timer_hash   = filesha256("${path.module}/scripts/state-backup.timer")
  }

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
      "sudo chown admin:admin /etc/state-backup/rclone.conf /etc/state-backup/age-recipient.txt",
      "sudo chmod 600 /etc/state-backup/rclone.conf /etc/state-backup/age-recipient.txt",
      "sudo apt-get update && sudo apt-get install -y curl age zstd unzip",
      "which mc >/dev/null || (curl -sL https://dl.min.io/client/mc/release/linux-amd64/mc -o /tmp/mc && sudo install /tmp/mc /usr/local/bin/mc)",
      "which rclone >/dev/null || (curl -sL https://rclone.org/install.sh | sudo bash)",
      "mc alias set homelab https://iapetus.orbit.solsys.dev:9000 '${var.minio_root_user}' '${var.minio_root_password}'",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable --now state-backup.timer"
    ]
  }
}

# ============================================================================
# MinIO TLS: certbot + Cloudflare DNS-01, placed at MinIO's expected
# certs-dir, with a certbot renewal deploy-hook to keep it current.
# minio-user has no home directory, so --certs-dir is set explicitly
# rather than relying on the $HOME/.minio/certs default.
# ============================================================================
resource "null_resource" "minio_tls_setup" {
  depends_on = [null_resource.state_backup_setup]

  connection {
    type  = "ssh"
    host  = "iapetus.orbit.solsys.dev"
    user  = "admin"
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update && sudo apt-get install -y certbot python3-certbot-dns-cloudflare",
      "sudo mkdir -p /etc/letsencrypt",
      "sudo tee /etc/letsencrypt/cloudflare.ini > /dev/null <<'CF_EOF'\ndns_cloudflare_api_token = ${var.minio_cloudflare_api_token}\nCF_EOF",
      "sudo chmod 600 /etc/letsencrypt/cloudflare.ini",
      "sudo certbot certonly --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini -d iapetus.orbit.solsys.dev -m admin@solsys.dev --agree-tos --non-interactive || true",
      "sudo mkdir -p /etc/minio/certs",
      "sudo cp /etc/letsencrypt/live/iapetus.orbit.solsys.dev/fullchain.pem /etc/minio/certs/public.crt",
      "sudo cp /etc/letsencrypt/live/iapetus.orbit.solsys.dev/privkey.pem /etc/minio/certs/private.key",
      "sudo chown -R minio-user:minio-user /etc/minio/certs",
      "sudo chmod 600 /etc/minio/certs/private.key",
      "sudo sed -i 's|MINIO_OPTS=\"--console-address :9001\"|MINIO_OPTS=\"--console-address :9001 --certs-dir /etc/minio/certs\"|' /etc/default/minio",
      "sudo tee /etc/letsencrypt/renewal-hooks/deploy/minio-reload.sh > /dev/null <<'HOOK_EOF'\n#!/usr/bin/env bash\ncp /etc/letsencrypt/live/iapetus.orbit.solsys.dev/fullchain.pem /etc/minio/certs/public.crt\ncp /etc/letsencrypt/live/iapetus.orbit.solsys.dev/privkey.pem /etc/minio/certs/private.key\nchown -R minio-user:minio-user /etc/minio/certs\nHOOK_EOF",
      "sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/minio-reload.sh",
      "sudo systemctl restart minio"
    ]
  }
}