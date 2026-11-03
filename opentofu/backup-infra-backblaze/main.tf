resource "b2_bucket" "barbapiccola_chain_b" {
  bucket_name = "barbapiccola-chain-b-backup"
  bucket_type = "allPrivate"

  # Matches the live bucket (found 2026-11-03: the plan wanted to remove it).
  default_server_side_encryption {
    algorithm = "AES256"
    mode      = "SSE-B2"
  }

  # Retention backstop per app (ADR-0054): the backup job deletes by age itself; this rule
  # removes the app's files even if the job is broken. Hide after max-1 days, delete a day later.
  dynamic "lifecycle_rules" {
    for_each = var.backup_apps
    content {
      file_name_prefix              = "${lifecycle_rules.key}-"
      days_from_uploading_to_hiding = var.backup_max_age_days - 1
      days_from_hiding_to_deleting  = 1
    }
  }
}

variable "backup_max_age_days" {
  description = "Hard upper age of any app backup in this bucket (privacy limit, ADR-0054)."
  type        = number
  default     = 13
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


# ---- Per-app backup keys (ADR-0054) -----------------------------------------------------
# One key per app, limited to the Chain B bucket AND to file names starting "<app>-", so a
# compromised app backup job can neither read nor delete another app's backups.
# Adding an app = adding its name here (and in backup-infra-ovhcloud).
variable "backup_apps" {
  description = "Apps with their own backup credentials. Their backup object names start with '<app>-'."
  type        = set(string)
  default     = ["forscher"]
}

resource "b2_application_key" "app_backup_writer" {
  for_each     = var.backup_apps
  key_name     = "${each.key}-backup-writer"
  bucket_ids   = [b2_bucket.barbapiccola_chain_b.id]
  name_prefix  = "${each.key}-"
  capabilities = ["listBuckets", "listFiles", "readFiles", "writeFiles", "deleteFiles"]
}

output "app_backup_keys" {
  description = "Per-app Chain B credentials: tofu output -json app_backup_keys"
  value = {
    for app, k in b2_application_key.app_backup_writer : app => {
      key_id     = k.application_key_id
      key_secret = k.application_key
    }
  }
  sensitive = true
}
