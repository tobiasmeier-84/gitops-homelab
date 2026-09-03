resource "b2_bucket" "barbapiccola_chain_b" {
  bucket_name = "barbapiccola-chain-b-backup"
  bucket_type = "allPrivate"
}

resource "b2_application_key" "backup_writer" {
  key_name     = "chain-b-backup-writer"
  bucket_ids   = [b2_bucket.barbapiccola_chain_b.id]
  capabilities = ["listBuckets", "listFiles", "readFiles", "writeFiles", "deleteFiles"]
}

output "b2_key_id" {
  value = b2_application_key.backup_writer.application_key_id
}

output "b2_key_secret" {
  value     = b2_application_key.backup_writer.application_key
  sensitive = true
}