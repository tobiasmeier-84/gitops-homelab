resource "ovh_cloud_project_storage" "scopuli" {
  service_name = var.ovh_project_id
  region_name  = "EU-WEST-PAR"
  name         = "scopuli-chain-a-backup"
}

resource "ovh_cloud_project_user" "backup_writer" {
  service_name = var.ovh_project_id
  description  = "Backup chain A writer (Serrio Mal-equivalent role for OVHcloud)"
  role_names   = ["objectstore_operator"]
}

resource "ovh_cloud_project_user_s3_credential" "backup_writer" {
  service_name = var.ovh_project_id
  user_id      = ovh_cloud_project_user.backup_writer.id
}

output "s3_access_key" {
  value = ovh_cloud_project_user_s3_credential.backup_writer.access_key_id
}

output "s3_secret_key" {
  value     = ovh_cloud_project_user_s3_credential.backup_writer.secret_access_key
  sensitive = true
}

resource "ovh_cloud_project_user_s3_policy" "backup_writer" {
  service_name = var.ovh_project_id
  user_id      = ovh_cloud_project_user.backup_writer.id
  policy = jsonencode({
    Statement = [{
      Sid    = "RWContainer"
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:ListMultipartUploadParts",
        "s3:ListBucketMultipartUploads",
        "s3:GetBucketVersioning",
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
      ]      
      Resource = [
        "arn:aws:s3:::scopuli-chain-a-backup",
        "arn:aws:s3:::scopuli-chain-a-backup/*",
      ]
    }]
  })
}


# ---- Per-app backup users (ADR-0054) ----------------------------------------------------
# One user per app. Its policy allows object access only for names "<app>-*" in the Chain A
# bucket (a user that does not own the bucket gets nothing that is not explicitly allowed).
# Bucket-level listing cannot be limited to a prefix, so the app can list names, not read them.
# Adding an app = adding its name here (and in backup-infra-backblaze).
variable "backup_apps" {
  description = "Apps with their own backup credentials. Their backup object names start with '<app>-'."
  type        = set(string)
  default     = ["forscher"]
}

resource "ovh_cloud_project_user" "app_backup_writer" {
  for_each     = var.backup_apps
  service_name = var.ovh_project_id
  description  = "Backup chain A writer for ${each.key} (prefix ${each.key}-)"
  role_names   = ["objectstore_operator"]
}

resource "ovh_cloud_project_user_s3_credential" "app_backup_writer" {
  for_each     = var.backup_apps
  service_name = var.ovh_project_id
  user_id      = ovh_cloud_project_user.app_backup_writer[each.key].id
}

resource "ovh_cloud_project_user_s3_policy" "app_backup_writer" {
  for_each     = var.backup_apps
  service_name = var.ovh_project_id
  user_id      = ovh_cloud_project_user.app_backup_writer[each.key].id
  policy = jsonencode({
    Statement = [
      {
        Sid    = "ListOwnBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
        ]
        Resource = ["arn:aws:s3:::scopuli-chain-a-backup"]
      },
      {
        Sid    = "OwnPrefixOnly"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload",
        ]
        Resource = ["arn:aws:s3:::scopuli-chain-a-backup/${each.key}-*"]
      },
    ]
  })
}

output "app_backup_keys" {
  description = "Per-app Chain A credentials: tofu output -json app_backup_keys"
  value = {
    for app, c in ovh_cloud_project_user_s3_credential.app_backup_writer : app => {
      access_key = c.access_key_id
      secret_key = c.secret_access_key
    }
  }
  sensitive = true
}
