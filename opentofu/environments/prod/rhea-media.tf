# ============================================================================
# behemoth media disk (created 2026-10-23)
# 14.6 TB USB drive (BUSLink Ciphershield, hardware-encrypted, own PSU on the UPS,
# unlocked with a physical key) plugged into pallas, passed through WHOLE to rhea
# (VM 203) as scsi7. Formatted/mounted by the Ansible role media-disk (ext4, label
# plexmedia, /mnt/behemoth). Plex (app "behemoth") uses it as a node-pinned local PV.
#
# backup=0: vzdump must never try to include a 14.6 TB passthrough disk.
# The guard makes this a no-op when scsi7 already exists. Never point it at
# razorback / rpool / Longhorn disks. rhea's other passthrough disks are in module.rhea.
# ============================================================================
resource "null_resource" "rhea_usb_media_passthrough" {
  triggers = {
    disk = "usb-BUSLINK_Ciphershield_1208010000F04000026-0:0"
  }

  depends_on = [module.rhea]

  connection {
    type  = "ssh"
    host  = "10.10.10.13"
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "test -e '/dev/disk/by-id/usb-BUSLINK_Ciphershield_1208010000F04000026-0:0' || { echo 'USB media disk not present on pallas'; exit 1; }",
      "qm config 203 | grep -q '^scsi7:' || qm set 203 --scsi7 '/dev/disk/by-id/usb-BUSLINK_Ciphershield_1208010000F04000026-0:0,backup=0'"
    ]
  }
}
