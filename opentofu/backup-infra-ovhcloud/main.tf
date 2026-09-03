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