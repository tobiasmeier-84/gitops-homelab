resource "b2_bucket" "state_backup" {
  bucket_name = "homelab-opentofu-state-backup"
  bucket_type = "allPrivate"
}

output "state_backup_bucket_id" {
  value = b2_bucket.state_backup.bucket_id
}
